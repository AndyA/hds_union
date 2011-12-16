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

1;

# vim:ts=2:sw=2:sts=2:et:ft=perl
