#!/usr/bin/env perl

package box;

use strict;
use warnings;

sub new { bless {}, shift }

sub read {
  my $self = shift;
  return { type => 'moov' };
}

sub _isa {
  my $self = shift;
  my $class = ref $self || $self;
  no strict 'refs';
  return @{"${class}::ISA"};
}

sub _hierarchy {
  my $self  = shift;
  my $class = ref $self || $self;
  my @h     = ( $class );
  while ( 1 ) {
    my @isa = $h[0]->_isa or last;
    unshift @h, @isa;
  }
  return @h;
}

sub read_box {
  my $self = shift;
  my $class = ref $self || $self;

  my %rec = ();
  for my $isa ( $self->_hierarchy ) {
    my $rc = $isa->can( 'read' )->( $self );
    %rec = ( %rec, %$rc );
  }
  return \%rec;
}

package fullbox;

use strict;
use warnings;

our @ISA = qw( box );

sub read {
  my $self = shift;
  return { version => 0, flags => 0xfff };
}

package mybox;

our @ISA = qw( fullbox );

use strict;
use warnings;

sub read {
  my $self = shift;
  return { name => 'My Box' };
}

package main;

use strict;
use warnings;

use Data::Dumper;

my $box = mybox->new;
print Dumper( $box->read_box );

# vim:ts=2:sw=2:sts=2:et:ft=perl

