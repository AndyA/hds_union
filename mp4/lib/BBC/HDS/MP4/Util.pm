package BBC::HDS::MP4::Util;

use strict;
use warnings;

use base qw( Exporter );

our @EXPORT = qw( make_resolver );

=head1 NAME

BBC::HDS::MP4::Util - Utility functions

=cut

sub make_resolver {
  my $hash = shift;
  return sub {
    my $box  = shift;
    my $type = $box->{type};
    return $hash->{$type} || $hash->{'*'};
  };
}

1;

# vim:ts=2:sw=2:sts=2:et:ft=perl
