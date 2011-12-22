package BBC::BoxML::Box;

use strict;
use warnings;

=head1 NAME

BBC::BoxML::Box - A Basic ISO 14496-12 box

=cut

sub new { bless { box => {} }, shift }

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

1;

# vim:ts=2:sw=2:sts=2:et:ft=perl
