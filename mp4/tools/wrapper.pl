#!/usr/bin/env perl

use strict;
use warnings FATAL => 'all';

use Data::Dumper;
use Path::Class;
use List::Util qw( max );

use lib qw( lib );

use BBC::HDS::MP4::IONullWriter;
use BBC::HDS::MP4::IOReader;
use BBC::HDS::MP4::IOWriter;
use BBC::HDS::MP4::Relocator;

my @CONTAINER = qw(
 dinf edts mdia minf moof moov
 mvex stbl traf trak udta
);

my $src  = shift @ARGV;
my $rdr  = BBC::HDS::MP4::IOReader->new( file( $src )->openr );
my $root = walk( $rdr, atom_smasher( iso_box_dec(), my $data = {} ) );
report( $data );
if ( @ARGV ) {
  my $dst = shift @ARGV;
  my $wtr = BBC::HDS::MP4::IOWriter->new( file( $dst )->openw );
  make_file( $wtr, reorg( $root ) );
}
else {
  #  layout( $root );
  print Data::Dumper->new( [$root] )->Indent( 2 )->Quotekeys( 0 )->Useqq( 1 )->Terse( 1 )
   ->Dump;
}

sub report {
  my $data = shift;
  print hist( "Unhandled boxes", $data->{meta}{unhandled} );
  print hist( "Captured boxes",  $data->{box} );
}

sub hist {
  my ( $title, $hash ) = @_;
  return unless keys %$hash;
  my $ldr  = '# ';
  my $size = sub {
    my $x = shift;
    return scalar @$x if 'ARRAY' eq ref $x;
    return $x;
  };
  my %hist = map { $_ => $size->( $hash->{$_} ) } keys %$hash;
  my @keys = sort { $hist{$b} <=> $hist{$a} } keys %hist;
  my $kw = max 1, map { length $_ } keys %hist;
  my $vw = max 1, map { length $_ } values %hist;
  my $fmt = "$ldr  %-${kw}s : %${vw}d\n";
  print "$ldr$title:\n";
  printf $fmt, $_, $hist{$_} for @keys;
}

sub escape {
  ( my $src = shift ) =~ s/ ( [ \x00-\x20 \x7f-\xff ] ) /
                            '\\x' . sprintf '%02x', ord $1 /exg;
  return $src;
}

### READING ###

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

sub make_resolver {
  my $hash = shift;
  return sub {
    my $box  = shift;
    my $type = $box->{type};
    return $hash->{$type} || $hash->{'*'};
  };
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
    $data->{meta}{unhandled}{ escape( scalar $rdr->path ) }++;
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
  my $rc  = $smasher->(
    BBC::HDS::MP4::IOReader->new( [ $rdr, $type ], $pos, $size - ( $pos - $box ) ),
    $smasher
  );
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

### WRITING ###

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
  write_boxes( BBC::HDS::MP4::IONullWriter->new,
    box_pusher( iso_box_enc( BBC::HDS::MP4::Relocator->null ) ), $root );
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
      die "Source / destination size mismatch: $ssz / $dsz" unless $ssz == $dsz;
      push @idx, [ $sst, $sen, $dst - $sst ];
    }
  }

  return @idx;
}

sub make_file {
  my ( $wtr, $boxes ) = @_;
  layout( $boxes );
  write_boxes( $wtr,
    box_pusher( iso_box_enc( BBC::HDS::MP4::Relocator->new( reloc_index( $boxes ) ) ) ),
    $boxes );
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

sub reorg {
  my $root = shift;
  my ( @last, @first );
  for my $box ( @$root ) {
    next unless defined $box;
    if ( $box->{type} eq 'mdat' ) {
      push @last, $box;
    }
    else {
      push @first, $box;
    }
  }
  return [ @first, @last ];
}

# vim:ts=2:sw=2:sts=2:et:ft=perl

