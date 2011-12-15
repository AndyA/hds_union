package BBC::HDS::Bootstrap::BoxWriter;

use strict;
use warnings;

use base qw( BBC::HDS::Bootstrap::ByteWriter );

=head1 NAME

BBC::HDS::Bootstrap::BoxWriter - Write Bootstrap boxes

=cut

sub new {
  my $class = shift;
  my $self  = $class->SUPER::new;
  $self->{type} = shift;
  return $self;
}

sub box {
  my $self = shift;
  my $data = $self->data;
  my $hdr  = BBC::HDS::Bootstrap::ByteWriter->new;
  $hdr->write32( length( $data ) + 8 );
  $hdr->write4CC( $self->{type} );
  return join '', $hdr->data, $data;
}

1;

# vim:ts=2:sw=2:sts=2:et:ft=perl
