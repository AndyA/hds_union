package BBC::HDS::MP4::IOReader;

use strict;
use warnings;

use Carp qw( croak );
use Data::Dumper;
use Data::Hexdumper;
use List::Util qw( min );

use base qw( BBC::HDS::MP4::IOBase );

=head1 NAME

BBC::HDS::MP4::IOReader - Read from an MP4

=cut

sub new {
  my ( $class, $from, $start, $size ) = @_;

  my ( $src, @loc ) = 'ARRAY' eq ref $from ? @$from : ( $from );

  my ( $fh, $cont_start, $cont_size, @path )
   = ( UNIVERSAL::can( $src, 'isa' ) && $src->isa( 'BBC::HDS::MP4::IOReader' ) )
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

sub readV {
  my ( $self, $long ) = @_;
  return $long ? $self->read64 : $self->read32;
}

sub dump {
  my ( $self, $len ) = @_;
  $len = 256 unless defined $len;
  my $here = $self->tell;
  $self->seek( 0, 0 );
  my $chunk = $self->read( $len );
  $self->seek( $here, 0 );
  return hexdump( $chunk );
}

1;

# vim:ts=2:sw=2:sts=2:et:ft=perl
