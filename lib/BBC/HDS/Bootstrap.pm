package BBC::HDS::Bootstrap;

use strict;
use warnings;

use base qw( BBC::HDS::Bootstrap::Container );

=head1 NAME

BBC::HDS::Bootstrap - An HDS bootstrap

=cut

use accessors::ro qw( data );

sub new {
  my $class = shift;
  return bless {@_}, $class;
}

sub _build_index {
  my $self = shift;
  my %idx  = ();
  for my $atom ( @{ $self->data } ) {
    my $type = $atom->{bi}{type};
    push @{ $idx{$type} }, $atom;
  }
  return \%idx;
}

sub index {
  my $self = shift;
  $self->{index} ||= $self->_build_index;
}

sub get_file_for_time {
  my ( $self, $time, $quality ) = @_;
  my $abst = $self->box( abst => 0 );
  my $afrt = $abst->box( afrt => 0 );
}

1;

# vim:ts=2:sw=2:sts=2:et:ft=perl
