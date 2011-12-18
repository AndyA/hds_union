#!/usr/bin/env perl

use strict;
use warnings;

use lib qw( lib );

use Data::Dumper;
use Data::Hexdumper;
use Path::Class;
use BBC::HDS::Bootstrap::Reader;
use BBC::HDS::Bootstrap::Writer;

my $src = shift @ARGV;
my $dst = "$src.out";

my $srcd = file( $src )->slurp;

my $rdr = BBC::HDS::Bootstrap::Reader->new( $srcd );
my $bs  = $rdr->parse;

print Dumper( $bs );

#my $wtr  = BBC::HDS::Bootstrap::Writer->new( $bs );
#my $dstd = $wtr->data;

#my $fh = file( $dst )->openw;
#print $fh $dstd;

#print hexdump( $dstd );

# vim:ts=2:sw=2:sts=2:et:ft=perl

