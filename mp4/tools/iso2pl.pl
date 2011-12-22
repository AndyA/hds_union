#!/usr/bin/env perl

use strict;
use warnings FATAL => 'all';

use Data::Dumper;

use lib qw( lib );

use BBC::HDS::MP4::Reader;

print Data::Dumper->new( [ BBC::HDS::MP4::Reader->parse( shift @ARGV ) ] )->Indent( 2 )
 ->Quotekeys( 0 )->Useqq( 1 )->Terse( 1 )->Dump;

# vim:ts=2:sw=2:sts=2:et:ft=perl

