package BBC::HDS::MP4::Writer;

use strict;
use warnings;

use Carp qw( croak confess );
use Scalar::Util qw( blessed );

use BBC::HDS::MP4::IONullWriter;
use BBC::HDS::MP4::IOWriter;
use BBC::HDS::MP4::Relocator;
use BBC::HDS::MP4::Util;

my @CONTAINER = qw(
 dinf edts mdia minf moof moov
 mvex stbl traf trak udta
);

=head1 NAME

BBC::HDS::MP4::Writer - Write MP4

=cut

sub write {
  my ( $class, $name, $boxes ) = @_;

  my $wtr = BBC::HDS::MP4::IOWriter->new( $name );

  my $lsz = layout( $boxes );
  write_boxes( $wtr,
    box_pusher( iso_box_enc( BBC::HDS::MP4::Relocator->new( reloc_index( $boxes ) ) ) ),
    $boxes );
  my $wsz = $wtr->tell;
  confess "Layout size: $lsz, written size: $wsz"
   unless $wsz == $lsz;
}

sub push_box {
  my ( $wtr, $pusher, $box, $long, $cb ) = @_;

  my $pos = $wtr->tell;

  $wtr->write32( 1 );
  $wtr->write4CC( $box->{type} );

  $wtr->write64( 1 ) if $long;

  $box->{_}{start} = $wtr->tell;
  $cb->( $wtr, $pusher, $box );
  $box->{_}{end} = my $end = $wtr->tell;

  if ( $long ) {
    $wtr->seek( $pos + 8, 0 );
    $wtr->write64( $end - $pos );
  }
  else {
    $wtr->seek( $pos, 0 );
    $wtr->write32( $end - $pos );
  }

  $wtr->seek( $end, 0 );
  return;
}

sub push_full(&) {
  my $cb = shift;
  return sub {
    my ( $wtr, $pusher, $box, @a ) = @_;
    $wtr->write8( $box->{version} );
    $wtr->write24( $box->{flags} );
    return $cb->( $wtr, $pusher, $box, @a );
  };
}

sub write_boxes {
  my ( $wtr, $pusher, $boxes ) = @_;
  for my $box ( @$boxes ) {
    next unless defined $box;
    $pusher->( $wtr, $pusher, $box );
  }
}

sub layout {
  my ( $root ) = @_;
  my $wtr = BBC::HDS::MP4::IONullWriter->new;
  write_boxes( $wtr, box_pusher( iso_box_enc( BBC::HDS::MP4::Relocator->null ) ), $root );
  return $wtr->tell;
}

sub reloc_index {
  my $boxes = shift;
  my @idx   = @_;

  for my $box ( @$boxes ) {
    next unless $box;
    if ( my $cont = $box->{boxes} ) {
      push @idx, reloc_index( $box->{boxes} );
    }
    elsif ( my $rdr = $box->{reader} ) {
      my ( $sst, $sen ) = $rdr->range;
      my ( $dst, $den ) = ( $box->{_}{start}, $box->{_}{end} );
      my $ssz = $sen - $sst;
      my $dsz = $den - $dst;
      confess "Source / destination size mismatch: $ssz / $dsz" unless $ssz == $dsz;
      push @idx, [ $sst, $sen, $dst - $sst ];
    }
  }

  return @idx;
}

sub iso_box_enc {
  my $reloc = shift;

  my $copy = sub {
    my ( $wtr, $pusher, $box ) = @_;

    my $rdr = $box->{reader};
    if ( $wtr->is_null ) {
      $wtr->seek( $rdr->size, 1 );
      return;
    }
    $rdr->seek( 0, 0 );
    while ( 1 ) {
      my $data = $rdr->read( 65536 );
      last unless length $data;
      $wtr->write( $data );
    }
  };

  my $magic = sub {
    my $encode = shift;
    my $rs     = make_resolver( $encode );
    return sub {
      my $box  = shift;
      my $hdlr = $rs->( $box );
      return $hdlr if $hdlr;
      return $copy if $box->{reader};
      return;
    };
  };

  my $container = sub {
    my ( $wtr, $pusher, $box ) = @_;
    write_boxes( $wtr, $pusher, $box->{boxes} );
  };

  my $nop = sub { };

  my $sample_entry = sub {
    my ( $wtr, $pusher, $box ) = @_;
    $wtr->write8( ( 0 ) x 6 );
    $wtr->write16( $box->{data_reference_index} );
  };

  my $visual_sample_entry = sub {
    $sample_entry->( @_ );
    my ( $wtr, $pusher, $box ) = @_;
    $wtr->write16( 0, 0 );
    $wtr->write32( 0, 0, 0 );
    $wtr->write16( $box->{width}, $box->{height} );
    $wtr->write32( $box->{horizresolution}, $box->{vertresolution} );
    $wtr->write32( 0 );
    $wtr->write16( $box->{frame_count} );
    $wtr->writeS( $box->{compressorname}, 32 );
    $wtr->write16( $box->{depth} );
    $wtr->write16( 0xffff );
  };

  my $avc_config = sub {
    my ( $wtr, $pusher, $box ) = @_;
    $wtr->write8(
      @{$box}{
        'configurationVersion',  'AVCProfileIndication',
        'profile_compatibility', 'AVCLevelIndication'
       },
      $box->{lengthSizeMinusOne} | 0xfc
    );

    my @sps = @{ $box->{sequenceParameterSetNALUnit} };
    $wtr->write8( scalar( @sps ) | 0xe0 );
    for my $el ( @sps ) {
      $wtr->write16( scalar @$el );
      $wtr->write8( @$el );
    }

    my @pps = @{ $box->{pictureParameterSetNALUnit} };
    $wtr->write8( scalar( @pps ) );
    for my $el ( @pps ) {
      $wtr->write16( scalar @$el );
      $wtr->write8( @$el );
    }
  };

  my $avc_sample_entry = sub {
    $visual_sample_entry->( @_ );
    my ( $wtr, $pusher, $box ) = @_;
    write_boxes( $wtr, $pusher, $box->{boxes} );
  };

  my %stsd = (
    avc1 => $avc_sample_entry,
    avcC => $avc_config,
  );

  my $encode = {
    # non-containers
    free => $nop,
    skip => $nop,
    stsd => push_full {
      my ( $wtr, undef, $box ) = @_;
      my $pusher = box_pusher( $magic->( \%stsd ) );
      $wtr->write32( scalar @{ $box->{boxes} } );
      write_boxes( $wtr, $pusher, $box->{boxes} );
    },
    stts => push_full {
      my ( $wtr, $pusher, $box ) = @_;
      my @ents = @{ $box->{entries} };
      $wtr->write32( scalar @ents );
      for my $e ( @ents ) {
        $wtr->write32( @{$e}{ 'sample_count', 'sample_data' } );
      }
    },
    stsz => push_full {
      my ( $wtr, $pusher, $box ) = @_;
      my @ents = @{ $box->{entries} };
      $wtr->write32( $box->{sample_size}, scalar( @ents ), @ents );
    },
    stss => push_full {
      my ( $wtr, $pusher, $box ) = @_;
      my @ents = @{ $box->{entries} };
      $wtr->write32( scalar( @ents ), @ents );
    },
    stsc => push_full {
      my ( $wtr, $pusher, $box ) = @_;
      my @ents = @{ $box->{entries} };
      $wtr->write32( scalar @ents );
      for my $e ( @ents ) {
        $wtr->write32(
          @{$e}{ 'first_chunk', 'samples_per_chunk', 'sample_description_index' } );
      }
    },
    mfhd => push_full {
      # UNTESTED
      my ( $wtr, $pusher, $box ) = @_;
      $wtr->write32( $box->{sequence_number} );
    },
    vmhd => push_full {
      my ( $wtr, $pusher, $box ) = @_;
      $wtr->write16( $box->{graphicsmode}, @{ $box->{opcolor} } );
    },
    smhd => push_full {
      my ( $wtr, $pusher, $box ) = @_;
      $wtr->write16( $box->{balance}, 0 );
    },
    nmhd => push_full { },
    hmhd => push_full {
      # UNTESTED
      my ( $wtr, $pusher, $box ) = @_;
      $wtr->write16( @{$box}{ 'maxPDUsize', 'avgPDUsize' } );
      $wtr->write32( @{$box}{ 'maxbitrate', 'avgbitrate', 'reserved' } );
    },
    tref => push_full {
      # UNTESTED
      my ( $wtr, $pusher, $box ) = @_;
      $wtr->write32( @{ $box->{track_IDs} } );
    },
    meta => push_full {
      my ( $wtr, $pusher, $box ) = @_;
      write_boxes( $wtr, $pusher, $box->{boxes} );
    },
    hdlr => push_full {
      my ( $wtr, $pusher, $box ) = @_;
      $wtr->write32( @{$box}{ 'pre_defined', 'handler_type' }, @{ $box->{unk1} } );
      $wtr->writeZ( $box->{name} );
    },
    mdhd => push_full {
      my ( $wtr, $pusher, $box ) = @_;
      my $ver = $box->{version};
      $wtr->writeV( $ver >= 1, @{$box}{ 'creation_time', 'modification_time' } );
      $wtr->write32( $box->{timescale} );
      $wtr->writeV( $ver >= 1, $box->{duration} );
      $wtr->write16( @{$box}{ 'language', 'pre_defined', } );
    },
    tkhd => push_full {
      my ( $wtr, $pusher, $box ) = @_;
      my $ver = $box->{version};

      $wtr->writeV( $ver >= 1, @{$box}{ 'creation_time', 'modification_time' } );
      $wtr->write32( $box->{track_ID}, 0 );
      $wtr->writeV( $ver >= 1, $box->{duration} );
      $wtr->write32( 0, 0 );
      $wtr->write16( @{$box}{ 'layer', 'alternate_group', 'volume' }, 0 );
      $wtr->write32( @{ $box->{matrix} }, $box->{width}, $box->{height}, );
    },
    mvhd => push_full {
      my ( $wtr, $pusher, $box ) = @_;
      my $ver = $box->{version};
      $wtr->writeV( $ver >= 1, @{$box}{ 'creation_time', 'modification_time' } );
      $wtr->write32( $box->{timescale} );
      $wtr->writeV( $ver >= 1, $box->{duration} );
      $wtr->write32( $box->{rate} );
      $wtr->write16( $box->{volume} );
      $wtr->write16( 0 );
      $wtr->write32( 0, 0 );
      $wtr->write32(
        @{ $box->{matrix} },
        @{ $box->{pre_defined} },
        $box->{next_track_ID}
      );
    },
    ftyp => push_full {
      my ( $wtr, $pusher, $box ) = @_;
      $wtr->write32( @{$box}{ 'major_brand', 'minor_version' },
        @{ $box->{compatible_brands} } );
    },
    tfhd => push_full {
      my ( $wtr, $pusher, $box ) = @_;
      my $fl = $box->{flags};

      $wtr->write32( $box->{track_ID} );
      $wtr->write64( $box->{base_data_offset}         || 0 ) if $fl & 0x000001;
      $wtr->write32( $box->{sample_description_index} || 0 ) if $fl & 0x000002;
      $wtr->write32( $box->{default_sample_duration}  || 0 ) if $fl & 0x000008;
      $wtr->write32( $box->{default_sample_size}      || 0 ) if $fl & 0x000010;
      $wtr->write32( $box->{default_sample_flags}     || 0 ) if $fl & 0x000020;
    },
    trun => push_full {
      my ( $wtr, $pusher, $box ) = @_;

      my $fl = $box->{flags};
      my @r  = $box->{run};

      $wtr->write32( scalar @r );

      $wtr->write32( $box->{data_offset}        || 0 ) if $fl & 0x001;
      $wtr->write32( $box->{first_sample_flags} || 0 ) if $fl & 0x004;

      for my $r ( @r ) {
        $wtr->write32( $box->{duration}    || 0 ) if $fl & 0x100;
        $wtr->write32( $box->{size}        || 0 ) if $fl & 0x200;
        $wtr->write32( $box->{flags}       || 0 ) if $fl & 0x400;
        $wtr->write32( $box->{time_offset} || 0 ) if $fl & 0x800;
      }
    },
    stco => push_full {
      my ( $wtr, $pusher, $box ) = @_;
      my @ofs = $reloc->reloc( @{ $box->{offsets} } );
      $wtr->write32( scalar( @ofs ), @ofs );
    },
    co64 => push_full {
      my ( $wtr, $pusher, $box ) = @_;
      my @ofs = $reloc->reloc( @{ $box->{offsets} } );
      $wtr->write32( scalar @ofs );
      $wtr->write64( @ofs );
    },
    ctts => push_full {
      my ( $wtr, $pusher, $box ) = @_;
      my @ofs = @{ $box->{offsets} };
      $wtr->write32( scalar @ofs );
      $wtr->write32( $_->{count}, $_->{offset} ) for @ofs;
    },
    url => push_full {
      my ( $wtr, $pusher, $box ) = @_;
      my $fl = $box->{flags};
      $wtr->writeZ( $box->{location} ) if !( $fl & 0x001 );
    },
    urn => push_full {
      my ( $wtr, $pusher, $box ) = @_;
      my $fl = $box->{flags};
      $wtr->writeZ( $box->{name} );
      $wtr->writeZ( $box->{location} ) if !( $fl & 0x001 );
    },
    dref => push_full {
      my ( $wtr, $pusher, $box ) = @_;
      $wtr->write32( scalar @{ $box->{dref} } );
      write_boxes( $wtr, $pusher, $box->{dref} );
    },
    elst => push_full {
      my ( $wtr, $pusher, $box ) = @_;
      my $ver  = $box->{version};
      my @list = @{ $box->{list} };
      $wtr->write32( scalar @list );
      for my $l ( @list ) {
        $wtr->writeV( $ver >= 1, $l->{segment_duration}, $l->{media_time} );
        $wtr->write16( $l->{media_rate_integer}, $l->{media_rate_fraction} );
      }
    },
    mehd => push_full {
      my ( $wtr, $pusher, $box ) = @_;
      my $ver = $box->{version};
      $wtr->writeV( $ver >= 1, $box->{fragment_duration} || 0 );
    },
    trex => push_full {
      my ( $wtr, $pusher, $box ) = @_;
      $wtr->write32(
        @{$box}{
          'track_ID',                'default_sample_description_index',
          'default_sample_duration', 'default_sample_size',
          'default_sample_flags',
         }
      );
    },
  };
  $encode->{$_} = $container for @CONTAINER;

  return $magic->( $encode );

}

sub box_pusher {
  my $encode = shift;

  my %IS_LONG = map { $_ => 1 } qw( mdat );

  return sub {
    my ( $wtr, $pusher, $box ) = @_;
    my $type = $box->{type};
    my $long = $IS_LONG{$type} || 0;
    my $hdlr = $encode->( $box );
    push_box( $wtr, $pusher, $box, $long, $hdlr ) if $hdlr;
  };
}

1;

# vim:ts=2:sw=2:sts=2:et:ft=perl
