#!/usr/bin/env perl

package io;

use strict;
use warnings;
use Carp qw( croak );

sub _whence_to_pos {
  my ( $self, $distance, $whence ) = @_;
  my $base
   = $whence == 0 ? 0
   : $whence == 1 ? $self->tell
   : $whence == 2 ? $self->size
   :                croak "Bad whence value";
  return $base + $distance;
}

package reader;

use strict;
use warnings;

our @ISA = qw( io );

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
  my $pos = $self->_whence_to_pos( $distance, $whence );
  croak "Seek out of range" if $pos < 0 || $pos > $self->size;
  $self->{pos} = $pos;
  $self;
}

sub start { shift->{start} }
sub tell  { shift->{pos} }
sub size  { shift->{size} }

sub range {
  my $self = shift;
  return ( $self->start, $self->start + $self->size );
}

sub avail {
  my $self = shift;
  return $self->size - $self->tell;
}

sub read {
  my ( $self, $len ) = @_;

  my $fh    = $self->{fh};
  my $pos   = $self->{pos} + $self->{start};
  my $avail = $self->{size} - $self->{pos};

  sysseek $fh, $pos, 0 or croak "Seek failed: $!\n";
  my $got = sysread $fh, my $data, min( $avail, $len );
  croak "I/O error: $!" unless defined $got;
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

package writer;

use strict;
use warnings;

use Carp qw( croak );

our @ISA = qw( io );

sub new {
  my ( $class, $fh ) = @_;
  return bless { fh => $fh, }, $class;
}

sub is_null { 0 }

sub write {
  my ( $self, $data ) = @_;
  my $put = syswrite $self->{fh}, $data;
  croak "I/O error: $!" unless defined $put;
  croak "Short write"   unless $put == length $data;
  $self;
}

sub write8   { shift->write( pack 'C*', @_ ) }
sub write16  { shift->write( pack 'n*', @_ ) }
sub write32  { shift->write( pack 'N*', @_ ) }
sub write4CC { shift->write( pack 'A4', @_ ) }

sub write24 {
  my ( $self, @data ) = @_;
  $self->write( pack 'Cn', ( $_ >> 16 ), $_ ) for @data;
  $self;
}

sub write64 {
  my ( $self, @data ) = @_;
  $self->write( pack 'NN', ( $_ >> 32 ), $_ ) for @data;
  $self;
}

sub writeZ {
  shift->write( map { "$_\0" } @_ );
}

sub write8ar {
  my ( $self, $cb, @data ) = @_;
  croak "Can't write more than 255 elements"
   if @data > 255;
  $self->write8( scalar @data );
  $cb->( $self, $_ ) for @data;
  $self;
}

sub write32ar {
  my ( $self, $cb, @data ) = @_;
  $self->write32( scalar @data );
  $cb->( $self, $_ ) for @data;
  $self;
}

sub writeZs {
  my ( $self, @ar ) = @_;
  $self->write8ar( sub { shift->writeZ( @_ ) }, @ar );
}

sub tell {
  my $pos = sysseek shift->{fh}, 0, 1;
  croak "Can't tell: $!" unless defined $pos;
  return $pos;
}

sub seek {
  my ( $self, $pos, $whence ) = @_;
  defined sysseek $self->{fh}, $pos, $whence
   or croak "Can't seek to $pos ($whence): $!";
}

package nullwriter;

use strict;
use warnings;
use Carp qw( croak );

our @ISA = qw( writer );

sub new { bless { pos => 0, size => 0 }, shift }

sub is_null { 1 }

sub write {
  my ( $self, $data ) = @_;
  $self->seek( length $data, 1 );
  $self;
}

sub tell { shift->{pos} }

sub seek {
  my ( $self, $distance, $whence ) = @_;
  my $pos = $self->_whence_to_pos( $distance, $whence );
  croak "Seek out of range" if $pos < 0;
  $self->{size} = $pos if $self->{size} < $pos;
  $self->{pos} = $pos;
  $self;
}

package main;

use strict;
use warnings;

use Data::Dumper;
use Path::Class;
use List::Util qw( max );

my @CONTAINER = qw(
 dinf edts mdia minf moof moov
 mvex stbl traf trak
);

my $src  = shift @ARGV;
my $rdr  = reader->new( file( $src )->openr );
my $root = walk( $rdr, atom_smasher( my $data = {} ) );
report( $data );
if ( @ARGV ) {
  my $dst = shift @ARGV;
  my $wtr = writer->new( file( $dst )->openw );
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
  my $rc = $smasher->( reader->new( [ $rdr, $type ], $pos, $size - ( $pos - $box ) ),
    $smasher );
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
  write_boxes( nullwriter->new, box_pusher( sub { @_ } ), $root );
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
    map { $reloc1->( @_ ) };
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

