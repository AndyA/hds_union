package BBC::HDS::Bootstrap;

use strict;
use warnings;

=head1 NAME

BBC::HDS::Bootstrap - An HDS bootstrap

=cut

use accessors::ro qw( bs );

sub new {
  my $class = shift;
  return bless {@_}, $class;
}

sub _build_index {
  my $self = shift;
  my %idx  = ();
  for my $atom ( @{ $self->bs } ) {
    my $type = $atom->{bi}{type};
    push @{ $idx{$type} }, $atom;
  }
  return \%idx;
}

sub index {
  my $self = shift;
  $self->{index} ||= $self->_build_index;
}

1;

# vim:ts=2:sw=2:sts=2:et:ft=perl
