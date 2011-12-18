#!/usr/bin/env perl

use strict;
use warnings;

use Data::Dumper;
use Getopt::Long;
use URI;

GetOptions( 'disable' => \my $disable, 'enable' => \my $enable ) or die;

sub networksetup(@);

my $if = get_interface();
if ( $enable || $disable ) {
  enable( $if, $enable );
}
elsif ( @ARGV ) {
  my $proxy = URI->new( shift @ARGV );
  networksetup '-setwebproxy', $if, $proxy->host, $proxy->port;
  enable( $if, 1 );
}
else {
  print "$_\n" for networksetup '-getwebproxy', $if;
}

sub networksetup(@) {
  my @args = @_;
  open my $ns, '-|', networksetup => @args
   or die "Can't open networksetup: $!\n";
  chomp( my @got = <$ns> );
  close $ns or die "Error running networksetup: $?\n";
  return @got;
}

sub enable {
  my ( $if, $on ) = @_;
  networksetup '-setwebproxystate', $if, $on ? 'on' : 'off';
}

sub get_interface {
  for ( networksetup '-listnetworkserviceorder' ) {
    return $1 if /^\(1\)\s+(.*)/;
  }
  return;
}

# vim:ts=2:sw=2:sts=2:et:ft=perl

