#!/usr/bin/env perl

use strict;
use warnings;

use Data::Dumper;
use Path::Class;
use List::Util qw( max );

use lib qw( lib );

use BBC::HDS::MP4::IOReader;
use BBC::HDS::MP4::IOWriter;
use BBC::HDS::MP4::IONullWriter;

my @CONTAINER = qw(
 dinf edts mdia minf moof moov
 mvex stbl traf trak
);

my $src  = shift @ARGV;
my $rdr  = BBC::HDS::MP4::IOReader->new( file( $src )->openr );
my $root = walk( $rdr, atom_smasher( my $data = {} ) );
report( $data );
if ( @ARGV ) {
  my $dst = shift @ARGV;
  my $wtr = BBC::HDS::MP4::IOWriter->new( file( $dst )->openw );
  make_file( $wtr, $root );
}
else {
  layout( $root );
  print Dumper( $root );
}

sub report {
  my $data = shift;
  print hist( "Unhandled boxes", $data->{meta}{unhandled} );
  print hist( "Captured boxes",  $data->{box} );
}

sub hist {
  my ( $title, $hash ) = @_;
  return unless keys %$hash;
  my $size = sub {
    my $x = shift;
    return scalar @$x if 'ARRAY' eq ref $x;
    return $x;
  };
  my %hist = map { $_ => $size->( $hash->{$_} ) } keys %$hash;
  my @keys = sort { $hist{$b} <=> $hist{$a} } keys %hist;
  my $kw = max 1, map { length $_ } keys %hist;
  my $vw = max 1, map { length $_ } values %hist;
  my $fmt = "  %-${kw}s : %${vw}d\n";
  print "$title:\n";
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

sub atom_smasher {
  my $data  = shift;
  my $depth = 0;

  my $drop = sub { return };

  my $keep = sub {
    my $rdr = shift;
    return { reader => $rdr, type => $rdr->fourCC };
  };

  my $walk = sub {
    my $rdr = shift;
    return { boxes => walk( $rdr, @_ ), type => $rdr->fourCC };
  };

  my %BOX = (
    #    mdia => $walk,
    #    minf => $walk,
    #    moov => $walk,
    #    stbl => $walk,
    #    trak => $walk,

    # moof specific
    #    dinf => $walk,
    #    edts => $walk,
    #    moof => $walk,
    #    mvex => $walk,
    #    traf => $walk,

    # bits we want to remember
    ftyp => $keep,
    mvhd => $keep,
    tkhd => $keep,
    mdhd => $keep,
    mdat => $keep,

    hdlr => $keep,
    udta => $keep,
    tref => $keep,

    # minf
    hmhd => $keep,
    nmhd => $keep,
    smhd => $keep,
    vmhd => $keep,

    # non-containers
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
      { dref => [ map { walk_box( $rdr, $smasher ) } 1 .. $rdr->read32 ] };
    },
    elst => full_box {
      my ( $rdr, $ver, $fl ) = @_;
      my $rw = $ver >= 1 ? sub { $rdr->read64 } : sub { $rdr->read32 };
      return {
        list => [
          map {
            {
              segment_duration    => $rw->(),
              media_time          => $rw->(),
              media_rate_integer  => $rdr->read16,
              media_rate_fraction => $rdr->read16,
            }
           } 1 .. $rdr->read32
        ]
      };
    },
    mehd => full_box {
      my ( $rdr, $ver, $fl ) = @_;
      return { fragment_duration => ( $ver >= 1 ) ? $rdr->read64 : $rdr->read32 };
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

    # ignore
    abst => $drop,
    afra => $drop,
    mfhd => $drop,
    free => $drop,

    # unknown
    stsc => $drop,
    stsd => $drop,
    stss => $drop,
    stsz => $drop,
    stts => $drop,
  );

  $BOX{$_} = $walk for @CONTAINER;

  my $cb = sub {
    my ( $rdr, $smasher ) = @_;
    my $pad  = '  ' x $depth;
    my $type = $rdr->fourCC;
    #    printf "%08x %10d%s%s\n", $rdr->start, $rdr->size, $pad, $type;
    if ( my $hdlr = $BOX{$type} ) {
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
  my ( $wtr, $box, $long, $cb ) = @_;

  my $pos = $wtr->tell;

  $wtr->write32( 1 );
  $wtr->write4CC( $box->{type} );

  $wtr->write64( 1 ) if $long;

  $box->{_}{start} = $wtr->tell;
  $cb->( $wtr, $box );
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
    my ( $wtr, $box, @a ) = @_;
    $wtr->write8( $box->{version} );
    $wtr->write24( $box->{flags} );
    return $cb->( $wtr, $box, @a );
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
  write_boxes( BBC::HDS::MP4::IONullWriter->new, box_pusher( sub { @_ } ), $root );
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

sub make_relocator {
  my $boxes = shift;

  my @idx = sort { $a->[0] <=> $b->[0] } reloc_index( $boxes );

  print Dumper( \@idx );

  my $reloc1 = sub {
    my ( $lo, $hi ) = ( 0, scalar @idx );
    while ( $lo < $hi ) {
    }
  };

  return sub {
    map { $reloc1->( $_ ) } @_;
  };
}

sub make_file {
  my ( $wtr, $boxes ) = @_;
  layout( $boxes );
  write_boxes( $wtr, box_pusher( make_relocator( $boxes ) ), $boxes );
}

sub box_pusher {
  my $reloc = shift;

  my $copy = sub {
    my ( $wtr, $pusher, $box, $long ) = @_;
    my $rdr = $box->{reader} || die;
    my $type = $rdr->fourCC;
    $long ||= $rdr->size > 0xffff0000;
    push_box(
      $wtr, $box, $long,
      sub {
        if ( $wtr->is_null ) {
          $wtr->seek( $rdr->size, 1 );
          return;
        }
        while ( 1 ) {
          my $data = $rdr->read( 65536 );
          last unless length $data;
          $wtr->write( $data );
        }
      }
    );
  };

  my $container = sub {
    my ( $wtr, $pusher, $box, $long ) = @_;
    push_box( $wtr, $box, $long, sub { write_boxes( $wtr, $pusher, $box->{boxes} ) } );
  };

  my %IS_LONG = map { $_ => 1 } qw( mdat );

  my %BOX = ();

  $BOX{$_} = $container for @CONTAINER;

  return sub {
    my ( $wtr, $pusher, $box ) = @_;

    my $type = $box->{type};
    print Dumper( $box )   unless defined $type;
    Carp::confess "Fucked" unless keys %$box;
    my $long = $IS_LONG{$type} || 0;

    # HACK
    $BOX{$type} = $copy if $box->{reader};

    if ( my $hdlr = $BOX{$type} ) {
      return $hdlr->( $wtr, $pusher, $box, $long );
    }
  };
}

# vim:ts=2:sw=2:sts=2:et:ft=perl

