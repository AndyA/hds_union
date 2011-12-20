#!/usr/bin/env perl

use strict;
use warnings;

use lib qw( lib );

use Data::Dumper;
use Data::Hexdumper;
use Path::Class;
use BBC::HDS::Bootstrap::Reader;

my $src  = shift @ARGV;
my $bs   = BBC::HDS::Bootstrap::Reader->load( $src );
my $abst = $bs->box( abst => 0 );
my $rt   = $abst->run_table;
print Dumper( $rt );

# vim:ts=2:sw=2:sts=2:et:ft=perl

