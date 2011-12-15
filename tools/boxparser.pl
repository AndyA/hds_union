#!/usr/bin/env perl

package main;

use strict;
use warnings;

use lib qw( lib );

use Data::Dumper;
use Path::Class;
use BBC::HDS::Bootstrap::Reader;

my $src = shift @ARGV;
my $bs  = file( $src )->slurp;
my $rdr = BBC::HDS::Bootstrap::Reader->new( $bs );
print Dumper( $rdr->parse );

# vim:ts=2:sw=2:sts=2:et:ft=perl

