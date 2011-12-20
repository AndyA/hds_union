package BBC::HDS::Bootstrap::ByteWriter;

use strict;
use warnings;

use Carp qw( croak );

=head1 NAME

BBC::HDS::Bootstrap::ByteWriter - Write bytes

=cut

sub new { bless { d => [] }, shift }

sub data { join '', @{ shift->{d} } }

sub write {
  my ( $self, @data ) = @_;
  push @{ $self->{d} }, @data;
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

1;

# vim:ts=2:sw=2:sts=2:et:ft=perl
