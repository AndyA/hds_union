package BBC::HDS::MP4::IOWriter;

use strict;
use warnings;

use Carp qw( croak );

use base qw( BBC::HDS::MP4::IOBase );

=head1 NAME

BBC::HDS::MP4::IOWriter - do something

=cut

sub new {
  my ( $class, $fh ) = @_;
  return bless { fh => $fh }, $class;
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

1;

# vim:ts=2:sw=2:sts=2:et:ft=perl
