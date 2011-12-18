#!/usr/bin/env perl

use strict;
use warnings;

use lib qw( lib );

use Data::Dumper;
use Data::Hexdumper;
use Path::Class;
use BBC::HDS::Bootstrap::Reader;

my $src = shift @ARGV;
print Data::Dumper->new(
  [ BBC::HDS::Bootstrap::Reader->load( $src )->data ] )->Indent( 2 )
 ->Quotekeys( 0 )->Useqq( 1 )->Terse( 1 )->Dump;

# vim:ts=2:sw=2:sts=2:et:ft=perl

