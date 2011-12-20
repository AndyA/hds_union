package BBC::HDS::MP4::IONullWriter;

use strict;
use warnings;

use Carp qw( croak );

use base qw( BBC::HDS::MP4::IOWriter );

=head1 NAME

BBC::HDS::MP4::IONullWriter - do something

=cut

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

1;

# vim:ts=2:sw=2:sts=2:et:ft=perl
