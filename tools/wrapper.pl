#!/usr/bin/env perl

package reader;

use strict;
use warnings;

use Carp qw( croak );
use List::Util qw( min );

sub new {
  my ( $class, $from, $start, $size ) = @_;

  my ( $src, @loc ) = 'ARRAY' eq ref $from ? @$from : ( $from );

  my ( $fh, $cont_start, $cont_size, @path )
   = ( UNIVERSAL::can( $src, 'isa' ) && $src->isa( 'reader' ) )
   ? $class->_fh_from_rdr( $src )
   : $class->_fh_from_fh( $src );

  $start = 0 unless defined $start;
  $size = $cont_size - $start unless defined $size;

  my $file_start = $start + $cont_start;

  croak "Larger than container"
   if $file_start + $size > $cont_start + $cont_size;

  return bless {
    fh    => $fh,
    start => $file_start,
    size  => $size,
    pos   => 0,
    path  => [ @path, @loc ],
  }, $class;
}

sub _fh_from_rdr {
  my ( $class, $rdr ) = @_;
  return ( $rdr->{fh}, $rdr->{start}, $rdr->{size}, @{ $rdr->{path} } );
}

sub _fh_from_fh {
  my ( $class, $fh ) = @_;
  my @st = stat $fh or croak "Can't stat handle: $!\n";
  return ( $fh, 0, $st[7] );
}

sub path {
  my @path = @{ shift->{path} };
  wantarray ? @path : join '/', @path;
}

sub fourCC { shift->{path}[-1] }

sub seek {
  my ( $self, $distance, $whence ) = @_;

  my $base
   = $whence == 0 ? 0
   : $whence == 1 ? $self->tell
   : $whence == 2 ? $self->{size}
   :                croak "Bad whence value";

  my $pos = $distance + $base;
  croak "Seek out of range" if $pos < 0 || $pos > $self->{size};
  $self->{pos} = $pos;
  $self;
}

sub start { shift->{start} }
sub tell  { shift->{pos} }
sub size  { shift->{size} }

sub avail {
  my $self = shift;
  return $self->size - $self->tell;
}

sub read {
  my ( $self, $len ) = @_;

  my $fh    = $self->{fh};
  my $pos   = $self->{pos} + $self->{start};
  my $avail = $self->{size} - $self->{pos};

  CORE::seek $fh, $pos, 0 or croak "Seek failed: $!\n";
  my $got = sysread $fh, my $data, min( $avail, $len );
  croak "IO Error: $!" unless defined $got;
  $self->{pos} += $got;
  return $data;
}

sub need {
  my ( $self, $len ) = @_;
  my $data = $self->read( $len );
  my $got  = length $data;
  croak "Short read ($got < $len)" unless $got == $len;
  return $data;
}

sub read8   { unpack 'C',  shift->need( 1 ) }
sub read16  { unpack 'n',  shift->need( 2 ) }
sub read32  { unpack 'N',  shift->need( 4 ) }
sub read4CC { unpack 'A4', shift->need( 4 ) }

sub read24 {
  my ( $hi, $lo ) = unpack 'Cn', shift->need( 3 );
  return ( $hi << 16 ) | $lo;
}

sub read64 {
  my ( $hi, $lo ) = unpack 'NN', shift->need( 8 );
  return ( $hi << 32 ) | $lo;
}

sub readZ {
  my $self = shift;
  my $tail = substr $self->{d}, $self->{p}, $self->{l};
  my $str  = ( $tail =~ /^(.*?)\0/ ) ? $1 : $tail;
  my $sz   = length( $str ) + 1;
  $self->{p} += $sz;
  $self->{l} -= $sz;
  return $str;
}

sub read8ar {
  my ( $self, $cb ) = @_;
  [ map { $cb->( $self ) } 1 .. $self->read8 ];
}

sub read32ar {
  my ( $self, $cb ) = @_;
  [ map { $cb->( $self ) } 1 .. $self->read32 ];
}

sub readZs { shift->read8ar( \&readZ ) }

package main;

use strict;
use warnings;

use Data::Dumper;
use Data::Hexdumper;
use Path::Class;
use List::Util qw( max );

my $src = shift;
my $rdr = reader->new( file( $src )->openr );
walk( $rdr, atom_smasher( my $data = {} ) );
report( $data );

sub report {
  my $data = shift;
  print hist( "Unhandled atoms", $data->{meta}{unhandled} );
  print hist( "Captured atoms",  $data->{atom} );
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

sub atom_smasher {
  my $data  = shift;
  my $depth = 0;

  my $drop = sub { return };
  my $walk = \&walk;
  my $keep = sub { my $rdr = shift; return $rdr };

  my %ATOM = (
    mdia => $walk,
    minf => $walk,
    moov => $walk,
    stbl => $walk,
    trak => $walk,
    udta => $walk,

    # moof specific
    dinf => $drop,
    edts => $walk,
    moof => $walk,
    mvex => $walk,
    traf => $walk,
    tref => $walk,

    # bits we want to remember
    ftyp => $keep,
    mdat => $keep,

    # non-containers
    trun => sub {
      my $rdr = shift;
      my ( $ver, $fl ) = parse_full_box( $rdr );
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
        return $trun;
      }
    },

    # TODO
    abst => $drop,
    afra => $drop,
    co64 => $drop,
    ctts => $drop,
    dref => $drop,
    elst => $drop,
    hdlr => $drop,
    hint => $drop,
    hmhd => $drop,
    mdhd => $drop,
    mehd => $drop,
    mfhd => $drop,
    mvhd => $drop,
    smhd => $drop,
    stsc => $drop,
    stsd => $drop,
    stss => $drop,
    stsz => $drop,
    stts => $drop,
    tfhd => $drop,
    tkhd => $drop,
    trex => $drop,
    vmhd => $drop,
  );

  my $cb = sub {
    my ( $rdr, $smasher ) = @_;
    my $pad    = '  ' x $depth;
    my $fourcc = $rdr->fourCC;
  #    printf "%08x %10d%s%s\n", $rdr->start, $rdr->size, $pad, $fourcc;
    if ( my $hdlr = $ATOM{$fourcc} ) {
      my $rc = $hdlr->( $rdr, $smasher );
      push @{ $data->{atom}{ $rdr->path } }, $rc
       if defined $rc;
    }
    else {
      $data->{meta}{unhandled}{ escape( $fourcc ) }++;
    }
  };

  return sub {
    $depth++;
    my $rc = $cb->( @_ );
    $depth--;
    return $rc;
  };
}

sub escape {
  ( my $src = shift ) =~ s/ ( [ \x00-\x20 \x7f-\xff ] ) /
                            '\\x' . sprintf '%02x', ord $1 /exg;
  return $src;
}

sub walk {
  my ( $rdr, $smasher ) = @_;
  while ( $rdr->avail ) {
    my $atom = $rdr->tell;
    my ( $size, $fourcc ) = parse_box( $rdr );
    my $pos = $rdr->tell;
    $smasher->(
      reader->new( [ $rdr, $fourcc ], $pos, $size - ( $pos - $atom ) ),
      $smasher
    );
    $rdr->seek( $atom + $size, 0 );
  }
  return;
}

sub parse_full_box {
  my $rdr = shift;
  return ( $rdr->read8, $rdr->read24 );
}

sub parse_box {
  my $rdr = shift;

  my ( $size, $fourcc ) = ( $rdr->read32, $rdr->read4CC );
  $size = $rdr->read64 if $size == 1;
  $size = $rdr->size   if $size == 0;

  return ( $size, $fourcc );

}

# vim:ts=2:sw=2:sts=2:et:ft=perl

