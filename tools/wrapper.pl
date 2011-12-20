#!/usr/bin/env perl

package reader;

use strict;
use warnings;

use Carp qw( croak );
use Data::Dumper;
use Data::Hexdumper;
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
  my @p    = ();
  my $pos  = $self->tell;
  while ( 1 ) {
    push @p, $self->read( 32 );
    croak "Unterminated string" unless length $p[-1];
    last if $p[-1] =~ s/\0.*//;
  }
  my $str = join '', @p;
  $self->seek( $pos + length( $str ) + 1, 0 );
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

sub dump {
  my ( $self, $len ) = @_;
  $len = 256 unless defined $len;
  my $here = $self->tell;
  $self->seek( 0, 0 );
  my $chunk = $self->read( $len );
  $self->seek( $here, 0 );
  return hexdump( $chunk );
}

package main;

use strict;
use warnings;

use Data::Dumper;
use Path::Class;
use List::Util qw( max );

my $src = shift;
my $rdr = reader->new( file( $src )->openr );
walk( $rdr, atom_smasher( my $data = {} ) );
report( $data );
print Dumper( $data->{atom}{'moov/trak/mdia/minf/dinf/dref'} );

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

sub make_dump {
  my $cb = shift;
  return sub {
    my $rdr = shift;
    print scalar( $rdr->path ), "\n";
    print $rdr->dump;
    $cb->( $rdr, @_ );
  };
}

sub atom_smasher {
  my $data  = shift;
  my $depth = 0;

  my $drop = sub { return };
  my $walk = \&walk;
  my $keep = sub { my $rdr = shift; return $rdr };

  my $ar32 = sub {
    my $rdr = shift;
    [ map { $rdr->read32 } 1 .. $rdr->read32 ];
  };

  my $ar64 = sub {
    my $rdr = shift;
    [ map { $rdr->read64 } 1 .. $rdr->read32 ];
  };

  my %ATOM = (
    mdia => $walk,
    minf => $walk,
    moov => $walk,
    stbl => $walk,
    trak => $walk,

    # moof specific
    dinf => $walk,
    edts => $walk,
    moof => $walk,
    mvex => $walk,
    traf => $walk,

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
      }
      return $trun;
    },
    stco => sub {
      my $rdr = shift;
      my ( $ver, $fl ) = parse_full_box( $rdr );
      $ar32->( $rdr );
    },
    co64 => sub {
      my $rdr = shift;
      my ( $ver, $fl ) = parse_full_box( $rdr );
      $ar64->( $rdr );
    },
    ctts => sub {
      my $rdr = shift;
      my ( $ver, $fl ) = parse_full_box( $rdr );
      {
        [ map { { count => $rdr->read32, offset => $rdr->read32, } }
           1 .. $rdr->read32 ];
      }
    },
    url => sub {
      my $rdr = shift;
      my ( $ver, $fl ) = parse_full_box( $rdr );
      return { location => $rdr->readZ };
    },
    urn => sub {
      my $rdr = shift;
      my ( $ver, $fl ) = parse_full_box( $rdr );
      return { name => $rdr->readZ, location => $rdr->readZ };
    },
    dref => $drop,
    #    dref => sub {
    #      my ( $rdr, $smasher ) = @_;
    #      print $rdr->dump;
    #      my ( $ver, $fl ) = parse_full_box( $rdr );
    #      [ map { walk_atom( $rdr, $smasher ) } 1 .. $rdr->read32 ];
    #    },
    elst => sub {
      my $rdr = shift;
      my ( $ver, $fl ) = parse_full_box( $rdr );
      [
        map {
          {
            ( $ver >= 1 )
             ? (
              segment_duration => $rdr->read64,
              media_time       => $rdr->read64,
             )
             : (
              segment_duration => $rdr->read32,
              media_time       => $rdr->read32,
             ),
             media_rate_integer  => $rdr->read16,
             media_rate_fraction => $rdr->read16,
          }
         } 1 .. $rdr->read32
      ];
    },

    # todo
    mehd => $drop,
    tfhd => $drop,
    trex => $drop,

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

  my $cb = sub {
    my ( $rdr, $smasher ) = @_;
    my $pad    = '  ' x $depth;
    my $fourcc = $rdr->fourCC;
  #    printf "%08x %10d%s%s\n", $rdr->start, $rdr->size, $pad, $fourcc;
    if ( my $hdlr = $ATOM{$fourcc} ) {
      my $rc = $hdlr->( $rdr, $smasher );
      if ( defined $rc ) {
        push @{ $data->{atom}{ $rdr->path } }, $rc;
        push @{ $data->{flat}{$fourcc} }, $rc;
      }
    }
    else {
      $data->{meta}{unhandled}{ escape( scalar $rdr->path ) }++;
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

sub walk_atom {
  my ( $rdr, $smasher ) = @_;
  my $atom = $rdr->tell;
  my ( $size, $fourcc ) = parse_box( $rdr );
  my $pos = $rdr->tell;
  my @rc  = $smasher->(
    reader->new( [ $rdr, $fourcc ], $pos, $size - ( $pos - $atom ) ),
    $smasher
  );
  $rdr->seek( $atom + $size, 0 );
  return @rc;
}

sub walk {
  my ( $rdr, $smasher ) = @_;
  my @rc = ();
  while ( $rdr->avail ) {
    push @rc, walk_atom( $rdr, $smasher );
  }
  return @rc;
}

sub parse_full_box {
  my $rdr = shift;
  return ( $rdr->read8, $rdr->read24 );
}

sub parse_box {
  my $rdr = shift;

  my ( $size, $fourcc ) = ( $rdr->read32, $rdr->read4CC );
  $fourcc =~ s/\s+$//;
  $size = $rdr->read64 if $size == 1;
  $size = $rdr->size   if $size == 0;

  return ( $size, $fourcc );

}

# vim:ts=2:sw=2:sts=2:et:ft=perl

