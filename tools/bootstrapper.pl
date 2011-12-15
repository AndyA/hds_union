#!/usr/bin/env perl

use strict;
use warnings;

use Data::Dumper;
use Data::Hexdumper;
use LWP::UserAgent;
use Path::Class;

#sub walk(@);
sub monitor_bootstrap(@);

#my $src = shift @ARGV;

#my $bs = file( $src )->slurp;

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

#walk $bs, sub {
#  my ( $size, $type, $data ) = @_;
#  if ( $type eq 'abst' ) {
#    my $hdr = substr $data, 0, 35;
#    walk substr( $data, 35 ), sub {
#      my ( $size, $type, $data ) = @_;
#      if ( $type eq 'asrt' ) {
#        return $size + 1;
#      }
#      elsif ( $type eq 'afrt' ) {
#        return $size + 1;
#      }
#      else {
#        die "Expected 'asrt', got '$type'\n";
#      }
#    };
#  }
#  else {
#    die "Expected 'abst', got '$type'\n";
#  }
#  return $size;
#};

sub walk(@) {
  my ( $data, $cb ) = @_;

  my $pos = 0;

  while ( $pos < length $data ) {
    my $size = unpack 'N', substr $data, $pos, 4;
    my $type = substr $data, $pos + 4, 4;
    $pos += 8;
    $size = length $data if $size == 0;
    print "$size, $type\n";
    print hexdump( substr $data, $pos, $size - 8 );
    $pos += $cb->( $size - 8, $type, substr $data, $pos, $size - 8 );
  }

}

# vim:ts=2:sw=2:sts=2:et:ft=perl

