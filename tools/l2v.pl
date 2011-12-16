#!/usr/bin/env perl

use strict;
use warnings;

use lib qw( lib );

use BBC::HDS::Bootstrap::Reader;
use Data::Dumper;
use Data::Hexdumper;
use LWP::UserAgent;
use MIME::Base64;
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
  print "Fetching $uri\n";
  my $resp = ua->get( $uri );
  die $resp->status_line unless $resp->is_success;
  my $doc = XML::LibXML->load_xml( string => $resp->content );
  my $xpc = XML::LibXML::XPathContext->new;
  $xpc->registerNs( m1 => 'http://ns.adobe.com/f4m/1.0' );
  $xpc->registerNs( m2 => 'http://ns.adobe.com/f4m/2.0' );
  return ( $doc, $xpc );
}

sub attr {
  my ( $elt, @name ) = @_;
  return map { $elt->getAttribute( $_ ) } @name;
}

sub tidy {
  my $str = shift;
  $str =~ s/^\s+//;
  $str =~ s/\s+$//;
  $str =~ s/\s+/ /g;
  return $str;
}

sub media_manifest {
  my $manifest = shift;

  my ( $f4m, $xpc ) = fetch_manifest( $manifest );
  my %bsi = ();
  my @bsi = $xpc->findnodes( '/m1:manifest/m1:bootstrapInfo', $f4m );
  for my $bs ( @bsi ) {
    my ( $profile, $url, $id ) = attr( $bs, 'profile', 'url', 'id' );
    $bsi{$id} = {
      profile => $profile,
      url     => URI->new_abs( $url, $manifest )
    };
  }

  my %stream = ();
  for my $media ( $xpc->findnodes( '/m1:manifest/m1:media', $f4m ) ) {
    my ( $stream_id, $url, $bi_id )
     = attr( $media, 'streamId', 'url', 'bootstrapInfoId' );
    my ( $metadata ) = $xpc->findnodes( 'm1:metadata', $media );

    # Don't do anything with the metadata yet
    my $md = decode_base64( tidy( $media->textContent ) );

    my $rec = {
      url => URI->new_abs( $url, $manifest ),
      bs  => $bsi{$bi_id},
    };
    $stream{$stream_id} = $rec;
  }

  return \%stream;
}

sub live2vod {
  my ( $manifest ) = @_;

  my ( $f4m, $xpc ) = fetch_manifest( $manifest );

  my %media = ();
  for my $media ( $xpc->findnodes( '/m2:manifest/m2:media', $f4m ) ) {
    my ( $href, $bitrate ) = attr( $media, 'href', 'bitrate' );
    $media{$bitrate}
     = media_manifest( URI->new_abs( $href, $manifest ) );
  }

  my @br = sort { $a <=> $b } keys %media;

  if ( @br ) {
    my $br  = shift @br;
    my @sid = sort keys %{ $media{$br} };
    if ( @sid ) {
      my $sid = shift @sid;
      follow_stream( $media{$br}{$sid} );
    }
  }

#http://fmshttpstg.bbc.co.uk.edgesuite-staging.net/hds-live/streams/livepkgr/streams/_definst_/inlet1/inlet1Seg1712-Frag17115
  print Dumper( \%media );

}

sub follow_stream {
  my $stream = shift;

  my $bs_uri = $stream->{bs}{url};

  monitor_bootstrap $bs_uri,
   back_off(
    min  => 5,
    max  => 60,
    rate => 1.2
   ),
   sub {
    my $resp = shift;
    if ( $resp->is_success ) {
      print "bootstrap\n";
    }
   };
}

# vim:ts=2:sw=2:sts=2:et:ft=perl

