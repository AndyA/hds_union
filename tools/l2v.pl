#!/usr/bin/env perl

use strict;
use warnings;

use lib qw( lib );

use BBC::HDS::Bootstrap::Merger;
use BBC::HDS::Bootstrap::Reader;
use BBC::HDS::Bootstrap::Writer;
use Data::Dumper;
use LWP::UserAgent;
use Path::Class;
use URI;
use XML::LibXML::XPathContext;
use XML::LibXML;

my $manifest = 'http://www.bbc.co.uk/test/zaphod/hds/emp_ak.f4m';

live2vod( $manifest );

#monitor_bootstrap $bs[0],
# back_off(
#  min  => 5,
#  max  => 60,
#  rate => 1.2
# ),
# sub {
#  my $resp = shift;
#  if ( $resp->is_success ) {
#    my $fn = sprintf 'bs/bs%05d.bootstrap', $next++;
#    print ">> $fn\n";
#    open my $fh, '>', $fn or die "Can't write $fn: $!\n";
#    print $fh $resp->content;
#  }
# };

sub ua() { LWP::UserAgent->new }

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

sub monitor_bootstrap {
  my ( $uri, $bo, $cb ) = @_;
  my $ua = ua;
  while ( 1 ) {
    my $resp = $ua->get( $uri );
    my $ttl  = $bo->( $resp );
    $cb->( $resp );
    last unless defined $ttl;
    sleep $ttl;
  }
}

sub fetch_manifest {
  my ( $uri ) = @_;
  my $resp = ua->get( $uri );
  die $resp->status_line unless $resp->is_success;
  return XML::LibXML->load_xml( string => $resp->content );
}

sub media_manifest {
  my $manifest = shift;
  my $f4m      = fetch_manifest( $manifest );
}

sub live2vod {
  my ( $manifest ) = @_;

  my $f4m = fetch_manifest( $manifest );
  my $xpc = XML::LibXML::XPathContext->new;
  $xpc->registerNs( m => 'http://ns.adobe.com/f4m/2.0' );

  my %media = ();
  for my $media ( $xpc->findnodes( '/m:manifest/m:media', $f4m ) ) {
    my $href
     = URI->new_abs( $media->getAttribute( 'href' ), $manifest );
    my $bitrate = $media->getAttribute( 'bitrate' );
    $media{$bitrate} = $href;
  }

}

# vim:ts=2:sw=2:sts=2:et:ft=perl

