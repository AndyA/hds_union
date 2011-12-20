#!/usr/bin/env perl

use strict;
use warnings;

use lib qw( lib );

use BBC::HDS::Bootstrap::Reader;
use Data::Dumper;
use Data::Hexdumper;
use Getopt::Long;
use LWP::UserAgent;
use MIME::Base64;
use Path::Class;
use Time::Timecode;
use URI;
use XML::LibXML::XPathContext;
use XML::LibXML;

use constant FPS => 25;
use constant DAY => 24 * 60 * 60;

my $Output = 'l2v';
GetOptions( 'output:s' => \$Output );

my $manifest = shift or die "Please supply a manifest URL";

live2vod( $manifest );

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
    print "Fetching $uri\n";
    my $resp = $ua->get( $uri );
    my $ttl  = $bo->( $resp );
    last unless $cb->( $resp );
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

  my $base = $manifest;
  for my $bu ( $xpc->findnodes( '/m2:manifest/m2:baseURL', $f4m ) ) {
    $base = URI->new_abs( $bu->textContent, $base );
  }

  my %media = ();
  for my $media ( $xpc->findnodes( '/m2:manifest/m2:media', $f4m ) ) {
    my ( $href, $bitrate ) = attr( $media, 'href', 'bitrate' );
    $media{$bitrate} = media_manifest( URI->new_abs( $href, $base ) );
  }

  download( \%media );

}

sub download {
  my $media = shift;
  my @br = sort { $a <=> $b } keys %$media;

  while ( my $br = shift @br ) {
    my @sid = sort keys %{ $media->{$br} };
    while ( my $sid = shift @sid ) {
      my $pid = fork;
      defined $pid or die "Can't fork";
      unless ( $pid ) {
        follow_stream( $media->{$br}{$sid} );
        exit;
      }
    }
  }

  1 while wait != -1;
}

sub follow_stream {
  my ( $stream ) = @_;

  my %got = ();

  my $bs_uri = $stream->{bs}{url};

  my $fetcher = sub {
    my ( $seg, $frag ) = @_;

    my $uri = URI->new( join '', $stream->{url}, sprintf 'Seg%d-Frag%d',
      $seg->{first}, $frag->{first} );

    return if $got{$uri}++;

    my @path = split /\//, $uri->path;
    my $base = pop @path;
    my $dir  = dir( $Output, @path );
    my $tmp  = file( $dir, "$base.tmp" );
    my $file = file( $dir, $base );

    $tmp->remove;
    return if -f $file;

    my $ts = as_timecode( $frag->{timestamp} / 1000 );
    print "[$ts] Fetching $uri\n";
    my $resp = ua->get( $uri );

    unless ( $resp->is_success ) {
      warn $resp->status_line, "\n";
      return;
    }

    $dir->mkpath;
    {
      my $fh = $tmp->openw;
      print $fh $resp->content;
    }

    rename $tmp, $file or die "Can't rename $tmp as $file\n";

  };

  monitor_bootstrap $bs_uri,
   back_off(
    min  => 5,
    max  => 60,
    rate => 1.2
   ),
   sub {
    my $resp = shift;
    return fetch_from_bootstrap( $resp->content, $fetcher )
     if $resp->is_success;
    return 1;
   };
}

sub fetch_from_bootstrap {
  my ( $bs_data, $cb ) = @_;
  my $bs = BBC::HDS::Bootstrap::Reader->new( $bs_data )->parse;
  my $abst = $bs->box( abst => 0 );
  die "No abst" unless $abst;

  my $rts = $abst->run_table;
  for my $rt ( @$rts ) {
    for my $seg ( @$rt ) {
      next unless $seg->{first};
      for my $frag ( @{ $seg->{f} } ) {
        if ( $frag->{duration} == 0 ) {
          #          return if $frag->{discontinuity};
          next;
        }
        $cb->( $seg, $frag );
      }
    }
  }
  return 1;
}

sub as_timecode {
  my $fr = $_[0] * FPS % ( DAY * FPS );
  Time::Timecode->new( $fr )->to_string;
}

# vim:ts=2:sw=2:sts=2:et:ft=perl

