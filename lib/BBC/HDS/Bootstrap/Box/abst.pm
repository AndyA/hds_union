package BBC::HDS::Bootstrap::Box::abst;

use strict;
use warnings;

use base qw( BBC::HDS::Bootstrap::Box );

=head1 NAME

BBC::HDS::Bootstrap::Box::abst - abst box

=cut

sub _build_index {
  my $self = shift;
  my $box  = $self->data;
  my @box  = (
    @{ $box->{segment_run_tables}  || [] },
    @{ $box->{fragment_run_tables} || [] }
  );
  my %idx = ();
  for my $box ( @box ) {
    my $type = $box->{bi}{type};
    push @{ $idx{$type} }, $box;
  }
  return \%idx;
}

sub index {
  my $self = shift;
  $self->{index} ||= $self->_build_index;
}

1;

# vim:ts=2:sw=2:sts=2:et:ft=perl
