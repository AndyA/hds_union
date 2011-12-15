#!/usr/bin/env perl

use strict;
use warnings;

use lib qw( lib );

use Data::Dumper;
use Path::Class;
use BBC::HDS::Bootstrap::Reader;
use BBC::HDS::Bootstrap::Writer;
use BBC::HDS::Bootstrap::Merger;

my $outf = shift @ARGV;
die unless defined $outf;
my @bs    = load( @ARGV );
my $mgr   = BBC::HDS::Bootstrap::Merger->new( @bs );
my $union = $mgr->merge;
my $wtr   = BBC::HDS::Bootstrap::Writer->new( $union );
{
  my $oh = file( $outf )->openw;
  print $oh $wtr->data;
}

# print Dumper( $union );

sub load {
  my @obj = @_;
  my @bs  = ();
  while ( defined( my $obj = shift @obj ) ) {
    if ( -d $obj ) {
      push @obj, dir( $obj )->children;
    }
    else {
      my $data = file( $obj )->slurp;
      push @bs, BBC::HDS::Bootstrap::Reader->new( $data )->parse;
    }
  }
  return @bs;
}

# vim:ts=2:sw=2:sts=2:et:ft=perl

