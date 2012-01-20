package BBC::HDS::MP4::Reader;

use strict;
use warnings;

use Carp qw( croak confess );
use Scalar::Util qw( blessed );

use BBC::HDS::MP4::IOReader;
use BBC::HDS::MP4::Util;

=head1 NAME

BBC::HDS::MP4::Reader - Read an MP4

=cut

my @CONTAINER = qw(
 dinf edts mdia minf moof moov
 mvex stbl traf trak udta
);

sub parse {
  my ( $class, $name, $data ) = @_;
  my $root = walk( BBC::HDS::MP4::IOReader->new( $name ),
    atom_smasher( iso_box_dec(), $data || {} ) );
  batten_down( $root );
  return $root;
}

sub visit(&$) {
  my ( $cb, $data ) = @_;

  return unless ref $data;

  if ( 'HASH' eq ref $data ) {
    return if exists $data->{type} && $cb->( $data );
    &visit( $cb, $_ ) for values %$data;
  }
  elsif ( 'ARRAY' eq ref $data ) {
    &visit( $cb, $_ ) for @$data;
  }
  else {
    confess "Not HASH or ARRAY";
  }
}

sub batten_down {
  my $data = shift;
  visit {
    my $box = shift;
    if ( my $rdr = $box->{reader} ) {
      $rdr->close;
      return 1;
    }
    return;
  }
  $data;
}

sub make_dump {
  my $cb = shift;
  return sub {
    my $rdr = shift;
    print scalar( $rdr->path ), "\n";
    print $rdr->dump;
    $cb->( $rdr, @_ );
  };
}

sub full_box(&) {
  my $cb = shift;
  return sub {
    my ( $rdr, @a )  = @_;
    my ( $ver, $fl ) = parse_full_box( $rdr );
    my $rc = $cb->( $rdr, $ver, $fl, @a );
    return { version => $ver, flags => $fl, type => $rdr->fourCC, %$rc };
  };
}

sub void { return }

sub iso_box_dec {
  my $drop = sub { return };

  my $keep = sub {
    my $rdr = shift;
    return { reader => $rdr, type => $rdr->fourCC };
  };

  my $walk = sub {
    my $rdr = shift;
    return { boxes => walk( $rdr, @_ ), type => $rdr->fourCC };
  };

  my $empty = sub { { type => shift->fourCC } };

  my $sample_entry = sub {
    my $rdr = shift;
    return {
      type                 => $rdr->fourCC,
      _1                   => [ map { $rdr->read8 } 1 .. 6 ],
      data_reference_index => $rdr->read16,
    };
  };

  my $visual_sample_entry = sub {
    my $rdr = shift;
    my $rec = $sample_entry->( $rdr );
    return {
      %$rec,
      type            => $rdr->fourCC,
      pre_defined_1   => $rdr->read16,
      _2              => $rdr->read16,
      pre_defined_2   => [ map { $rdr->read32 } 1 .. 3 ],
      width           => $rdr->read16,
      height          => $rdr->read16,
      horizresolution => $rdr->read32,
      vertresolution  => $rdr->read32,
      _3              => $rdr->read32,
      frame_count     => $rdr->read16,
      compressorname  => $rdr->readS( 32 ),
      depth           => $rdr->read16,
      pre_defined_3   => $rdr->read16,
    };
    # TODO CleanApertureBox, PixelAspectRatioBox
  };

  my $avc_config = sub {
    my $rdr = shift;
    return {
      type                        => $rdr->fourCC,
      configurationVersion        => $rdr->read8,
      AVCProfileIndication        => $rdr->read8,
      profile_compatibility       => $rdr->read8,
      AVCLevelIndication          => $rdr->read8,
      lengthSizeMinusOne          => $rdr->read8 & 0x03,
      sequenceParameterSetNALUnit => [
        map {
          [ map { $rdr->read8 } 1 .. $rdr->read16 ]
         } 1 .. $rdr->read8 & 0x1f
      ],
      pictureParameterSetNALUnit => [
        map {
          [ map { $rdr->read8 } 1 .. $rdr->read16 ]
         } 1 .. $rdr->read8
      ],
    };
  };

  my $avc_sample_entry = sub {
    my ( $rdr, $smasher ) = @_;
    my $vse = $visual_sample_entry->( $rdr );
    return { %$vse, type => $rdr->fourCC, boxes => walk( $rdr, $smasher ) };
  };

  my %stsd = (
    soun => $keep,
    vide => $keep,
    hint => $keep,
    meta => $keep,
    avc1 => $avc_sample_entry,
    avcC => $avc_config,
    '*'  => $keep,
  );

  my $decode = {
    # bits we want to remember
    mdat => $keep,

    # Adobe specific
    abst => $keep,
    afra => $keep,

    # TODO

    free => $empty,
    nmhd => $empty,
    skip => $empty,

    # format unknown
    ilst => $keep,

    # non-containers
    stsd => full_box {
      my $rdr = shift;
      my $smasher = atom_smasher( make_resolver( \%stsd ), {} );
      return { boxes => [ map { walk_box( $rdr, $smasher ) } 1 .. $rdr->read32 ] };
    },
    stts => full_box {
      my $rdr = shift;
      {
        entries => [
          map { { sample_count => $rdr->read32, sample_data => $rdr->read32, } }
           1 .. $rdr->read32
        ]
      };
    },
    stsz => full_box {
      my $rdr = shift;
      {
        sample_size => $rdr->read32,
        entries     => [ map { $rdr->read32 } 1 .. $rdr->read32 ]
      };
    },
    stss => full_box {
      my $rdr = shift;
      { entries => [ map { $rdr->read32 } 1 .. $rdr->read32 ] };
    },
    stsc => full_box {
      my $rdr = shift;
      {
        entries => [
          map {
            {
              first_chunk              => $rdr->read32,
              samples_per_chunk        => $rdr->read32,
              sample_description_index => $rdr->read32,
            }
           } 1 .. $rdr->read32
        ]
      };
    },
    mfhd => full_box {
      # UNTESTED
      my $rdr = shift;
      return { sequence_number => $rdr->read32 };
    },
    vmhd => full_box {
      my $rdr = shift;
      return {
        graphicsmode => $rdr->read16,
        opcolor      => [ map { $rdr->read16 } 1 .. 3 ],
      };
    },
    smhd => full_box {
      my $rdr = shift;
      return {
        balance => $rdr->read16,
        _1      => $rdr->read16,
      };
    },
    nmhd => full_box { {} },
    hmhd => full_box {
      # UNTESTED
      my $rdr = shift;
      return {
        maxPDUsize => $rdr->read16,
        avgPDUsize => $rdr->read16,
        maxbitrate => $rdr->read32,
        avgbitrate => $rdr->read32,
        reserved   => $rdr->read32,
      };
    },
    tref => full_box {
      # UNTESTED
      my $rdr = shift;
      my @ids = ();
      push @ids, $rdr->read32 while $rdr->avail;
      return { track_IDs => \@ids };
    },
    meta => full_box {
      my ( $rdr, $ver, $fl, @a ) = @_;
      return { boxes => walk( $rdr, @a ) };
    },
    hdlr => full_box {
      my $rdr = shift;
      return {
        pre_defined  => $rdr->read32,
        handler_type => $rdr->read32,
        unk1         => [ map { $rdr->read32 } 1 .. 3 ],
        name         => $rdr->readZ,
      };
    },
    mdhd => full_box {
      my ( $rdr, $ver, $fl ) = @_;
      return {
        creation_time     => $rdr->readV( $ver >= 1 ),
        modification_time => $rdr->readV( $ver >= 1 ),
        timescale         => $rdr->read32,
        duration          => $rdr->readV( $ver >= 1 ),
        language          => $rdr->read16,
        pre_defined       => $rdr->read16,
      };
    },
    tkhd => full_box {
      my ( $rdr, $ver, $fl ) = @_;
      return {
        creation_time     => $rdr->readV( $ver >= 1 ),
        modification_time => $rdr->readV( $ver >= 1 ),
        track_ID          => $rdr->read32,
        _1                => $rdr->read32,
        duration          => $rdr->readV( $ver >= 1 ),
        _2                => [ $rdr->read32, $rdr->read32 ],
        layer             => $rdr->read16,
        alternate_group   => $rdr->read16,
        volume            => $rdr->read16,
        _3                => $rdr->read16,
        matrix            => [ map { $rdr->read32 } 1 .. 9 ],
        width             => $rdr->read32,
        height            => $rdr->read32,
      };
    },
    mvhd => full_box {
      my ( $rdr, $ver, $fl ) = @_;
      return {
        creation_time     => $rdr->readV( $ver >= 1 ),
        modification_time => $rdr->readV( $ver >= 1 ),
        timescale         => $rdr->read32,
        duration          => $rdr->readV( $ver >= 1 ),
        rate              => $rdr->read32,
        volume            => $rdr->read16,
        _1                => [ $rdr->read16, $rdr->read32, $rdr->read32 ],
        matrix        => [ map { $rdr->read32 } 1 .. 9 ],
        pre_defined   => [ map { $rdr->read32 } 1 .. 6 ],
        next_track_ID => $rdr->read32,
      };
    },
    ftyp => full_box {
      my $rdr  = shift;
      my $ftyp = {
        major_brand       => $rdr->read32,
        minor_version     => $rdr->read32,
        compatible_brands => [],
      };
      push @{ $ftyp->{compatible_brands} }, $rdr->read32 while $rdr->avail;
      return $ftyp;
    },
    tfhd => full_box {
      my ( $rdr, $ver, $fl ) = @_;
      return {
        track_ID => $rdr->read32,
        ( $fl & 0x000001 ) ? ( base_data_offset         => $rdr->read64 ) : (),
        ( $fl & 0x000002 ) ? ( sample_description_index => $rdr->read32 ) : (),
        ( $fl & 0x000008 ) ? ( default_sample_duration  => $rdr->read32 ) : (),
        ( $fl & 0x000010 ) ? ( default_sample_size      => $rdr->read32 ) : (),
        ( $fl & 0x000020 ) ? ( default_sample_flags     => $rdr->read32 ) : (),
      };
    },
    trun => full_box {
      my ( $rdr, $ver, $fl ) = @_;
      my $sample_count = $rdr->read32;
      my $trun         = {
        ( $fl & 0x001 ) ? ( data_offset        => $rdr->read32 ) : (),
        ( $fl & 0x004 ) ? ( first_sample_flags => $rdr->read32 ) : (),
        run => [],
      };
      for ( 1 .. $sample_count ) {
        push @{ $trun->{run} },
         {
          ( $fl & 0x100 ) ? ( duration    => $rdr->read32 ) : (),
          ( $fl & 0x200 ) ? ( size        => $rdr->read32 ) : (),
          ( $fl & 0x400 ) ? ( flags       => $rdr->read32 ) : (),
          ( $fl & 0x800 ) ? ( time_offset => $rdr->read32 ) : (),
         };
      }
      return $trun;
    },
    stco => full_box {
      my $rdr = shift;
      { offsets => [ map { $rdr->read32 } 1 .. $rdr->read32 ] };
    },
    co64 => full_box {
      my $rdr = shift;
      { offsets => [ map { $rdr->read64 } 1 .. $rdr->read32 ] };
    },
    ctts => full_box {
      my $rdr = shift;
      { offsets =>
         [ map { { count => $rdr->read32, offset => $rdr->read32, } } 1 .. $rdr->read32 ]
      };
    },
    url => full_box {
      my ( $rdr, $ver, $fl ) = @_;
      return { flags => $fl, ( $fl & 0x001 ) ? () : ( location => $rdr->readZ ) };
    },
    urn => full_box {
      my ( $rdr, $ver, $fl ) = @_;
      return {
        name => $rdr->readZ,
        ( $fl & 0x001 ) ? () : ( location => $rdr->readZ )
      };
    },
    dref => full_box {
      my ( $rdr, $ver, $fl, $smasher ) = @_;
      return { dref => [ map { walk_box( $rdr, $smasher ) } 1 .. $rdr->read32 ] };
    },
    elst => full_box {
      my ( $rdr, $ver, $fl ) = @_;
      return {
        list => [
          map {
            {
              segment_duration    => $rdr->readV( $ver >= 1 ),
              media_time          => $rdr->readV( $ver >= 1 ),
              media_rate_integer  => $rdr->read16,
              media_rate_fraction => $rdr->read16,
            }
           } 1 .. $rdr->read32
        ]
      };
    },
    mehd => full_box {
      my ( $rdr, $ver, $fl ) = @_;
      return { fragment_duration => $rdr->readV( $ver >= 1 ) };
    },
    trex => full_box {
      my ( $rdr, $ver, $fl ) = @_;
      return {
        track_ID                         => $rdr->read32,
        default_sample_description_index => $rdr->read32,
        default_sample_duration          => $rdr->read32,
        default_sample_size              => $rdr->read32,
        default_sample_flags             => $rdr->read32,
      };
    },
  };

  $decode->{$_} = $walk for @CONTAINER;

  return make_resolver( $decode );
}

sub atom_smasher {
  my ( $decode, $data ) = @_;
  my $depth = 0;

  my $cb = sub {
    my ( $rdr, $smasher ) = @_;
    my $pad  = '  ' x $depth;
    my $type = $rdr->fourCC;
    printf "# %08x %10d%s%s\n", $rdr->start, $rdr->size, $pad, $type;
    if ( my $hdlr = $decode->( { type => $type } ) ) {
      my $rc = $hdlr->( $rdr, $smasher );
      push @{ $data->{box}{ $rdr->path } }, $rc;
      push @{ $data->{flat}{$type} }, $rc;
      return $rc;
    }
    $data->{meta}{unhandled}{ scalar $rdr->path }++;
    return;
  };

  return sub {
    $depth++;
    my $rc = $cb->( @_ );
    $depth--;
    return $rc;
  };
}

sub parse_full_box {
  my $rdr = shift;
  return ( $rdr->read8, $rdr->read24 );
}

sub parse_box {
  my $rdr = shift;

  my ( $size, $type ) = ( $rdr->read32, $rdr->read4CC );
  $type =~ s/\s+$//;
  $size = $rdr->read64 if $size == 1;
  $size = $rdr->size   if $size == 0;

  return ( $size, $type );
}

sub walk_box {
  my ( $rdr, $smasher ) = @_;
  my $box = $rdr->tell;
  my ( $size, $type ) = parse_box( $rdr );
  my $pos = $rdr->tell;
  my $end = $size - ( $pos - $box );
  my $rc
   = $smasher->( BBC::HDS::MP4::IOReader->new( [ $rdr, $type ], $pos, $end ), $smasher );
  $rdr->seek( $box + $size, 0 );
  return $rc;
}

sub walk {
  my ( $rdr, $smasher ) = @_;
  my @rc = ();
  while ( $rdr->avail ) {
    push @rc, walk_box( $rdr, $smasher );
  }
  return \@rc;
}

1;

# vim:ts=2:sw=2:sts=2:et:ft=perl
