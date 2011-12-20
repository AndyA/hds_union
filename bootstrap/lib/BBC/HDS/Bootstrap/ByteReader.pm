package BBC::HDS::Bootstrap::ByteReader;

use strict;
use warnings;

use Carp qw( croak );

=head1 NAME

BBC::HDS::Bootstrap::ByteReader - Read bytes

=cut

sub new {
  my ( $class, $data, $pos, $len ) = @_;
  $pos = 0 unless defined $pos;
  $len = length( $data ) - $pos unless defined $len;
  return bless {
    d => $data,
    p => $pos,
    l => $len,
  }, $class;
}

sub read {
  my ( $self, $count ) = @_;
  return $$self->{len} if $count < 0;

  croak "Truncated read at offset $self->{p}"
   if $self->{l} < $count;

  my $chunk = substr $self->{d}, $self->{p}, $count;
  $self->{p} += $count;
  $self->{l} -= $count;
  return $chunk;
}

sub avail { shift->{l} }
sub pos   { shift->{p} }

sub read8   { unpack 'C',  shift->read( 1 ) }
sub read16  { unpack 'n',  shift->read( 2 ) }
sub read32  { unpack 'N',  shift->read( 4 ) }
sub read4CC { unpack 'A4', shift->read( 4 ) }

sub read24 {
  my ( $hi, $lo ) = unpack 'Cn', shift->read( 3 );
  return ( $hi << 16 ) | $lo;
}

sub read64 {
  my ( $hi, $lo ) = unpack 'NN', shift->read( 8 );
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

1;

# vim:ts=2:sw=2:sts=2:et:ft=perl
