#!/usr/bin/env perl

use strict;
use warnings;

use LWP::UserAgent;

sub monitor_bootstrap(@);

my @bs = qw(
 http://fmshttpstg.bbc.co.uk.edgesuite-staging.net/hds-live/streams/livepkgr/streams/_definst_/inlet5/inlet5.bootstrap
);

monitor_bootstrap $bs[0],
 back_off(
  min  => 5,
  max  => 60,
  rate => 1.2
 ),
 sub {
  my $resp = shift;
  $resp->content( '' );
  print Dumper( $resp );
 };

sub back_off {
  my %a        = @_;
  my $back_off = $a{min};

  return sub {
    my $resp = shift;

    if ( $resp->is_success ) {
      $back_off = $a{min};
      return $resp->freshness_lifetime(
        heuristic_expiry => 0,
        h_min            => 1,
      );
    }

    my $ttl = int( $back_off );
    $back_off *= $a{rate};
    $back_off = $a{max} if $back_off > $a{max};
    return $ttl;
  };
}

sub monitor_bootstrap(@) {
  my ( $url, $bo, $cb ) = @_;
  my $ua = LWP::UserAgent->new;
  while ( 1 ) {
    my $resp = $ua->get( $url );
    my $ttl  = $bo->( $resp );
    $cb->( $resp );
    last unless defined $ttl;
    sleep $ttl;
  }
}

# vim:ts=2:sw=2:sts=2:et:ft=perl

