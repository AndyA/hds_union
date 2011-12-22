#!/usr/bin/env perl

use strict;
use warnings FATAL => 'all';

use Data::Dumper;

use lib qw( lib );

use BBC::HDS::MP4::Reader;
use BBC::HDS::MP4::Writer;

my $dst = shift @ARGV or die "Please name a file";
my $root = eval do { local $/; <> };
die $@ if $@;
BBC::HDS::MP4::Writer->write( $dst, $root );

# vim:ts=2:sw=2:sts=2:et:ft=perl

