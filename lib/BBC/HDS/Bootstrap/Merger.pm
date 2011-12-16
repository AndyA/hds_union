package BBC::HDS::Bootstrap::Merger;

use strict;
use warnings;

use Data::Dumper;
use List::Util qw( max );
use Carp qw( croak );

=head1 NAME

BBC::HDS::Bootstrap::Merger - Merge bootstraps

=cut

sub new {
  my $class = shift;
  return bless { bs => [@_] }, $class;
}

sub merge {
  my $self = shift;
  return $self->_reduce( map { $_->bs } @{ $self->{bs} } );
}

sub _reduce {
  my ( $self, $lhs, @bs ) = @_;
  $lhs = $self->_merge( '', $lhs, $_ ) for @bs;
  return $lhs;
}

sub _uniq {
  my %seen = ();
  return grep { !$seen{$_}++ } @_;
}

sub _atom_index {
  my ( $self, $ar ) = @_;
  my %idx = ();
  for my $atom ( @$ar ) {
    my $type = $atom->{bi}{type};
    push @{ $idx{$type} }, $atom;
  }
  return \%idx;
}

sub _merge_atom_list {
  my ( $self, $path, $lhs, $rhs ) = @_;
  $DB::single = 1;
  my $idx = $self->_atom_index( $rhs );
  my @m   = ();
  for my $la ( @$lhs ) {
    my $type = $la->{bi}{type};
    my $ra   = shift @{ $idx->{$type} };
    push @m, $self->_merge( $path, $la, $ra );
  }
  push @m, map { @$_ } values %$idx;
  return \@m;
}

sub _max {
  my ( $self, $path, $lhs, $rhs ) = @_;
  return max( $lhs, $rhs );
}

sub _zip {
  my ( $self, $path, $lhs, $rhs ) = @_;
  my @m = ();
  my $npath = join '/', $path, '*';
  for my $idx ( 0 .. max( $#$lhs, $#$rhs ) ) {
    push @m, $self->_merge( $npath, $lhs->[$idx], $rhs->[$idx] );
  }
  return \@m;
}

sub _merge_arrays {
  my ( $self, $path, $lhs, $rhs, $key ) = @_;

  return $lhs unless defined $rhs;
  return $rhs unless defined $lhs;

  # Ascending by key
  my @m = map { $_->[1] }
   sort { $a->[0] <=> $b->[0] } map { [ $_->{$key}, $_ ] } @$lhs, @$rhs;

  my @mm = ();
  my $npath = join '/', $path, '*';
  while ( my $next = shift @m ) {
    while ( @m && $m[0]{$key} == $next->{$key} ) {
      my $dup = shift @m;
      $next = $self->_merge( $npath, $next, $dup );
    }
    push @mm, $next;
  }

  return \@mm;
}

sub _runs {
  my ( $self, $path, $lhs, $rhs ) = @_;
  return $self->_merge_arrays( $path, $lhs, $rhs, 'first' );
}

{
  my %RULES = (
    '/*'                                       => \&_merge_atom_list,
    '/*/current_media_time'                    => \&_max,
    '/*/segment_run_tables'                    => \&_zip,
    '/*/segment_run_tables/*/runs'             => \&_runs,
    '/*/segment_run_tables/*/runs/*/frags'     => \&_max,
    '/*/fragment_run_tables'                   => \&_zip,
    '/*/fragment_run_tables/*/runs'            => \&_runs,
    '/*/fragment_run_tables/*/runs/*/duration' => \&_max,
  );

  sub _merge {
    my ( $self, $path, $lhs, $rhs ) = @_;

    return $rhs unless defined $lhs;
    return $lhs unless defined $rhs;

    if ( ref $lhs ) {
      croak "Mismatch ref / non ref at $path"
       unless ref $rhs;

      my ( $lr, $rr ) = ( ref $lhs, ref $rhs );

      croak "Mismatch $lr / $rr at $path"
       unless $lr eq $rr;

      if ( 'HASH' eq $lr ) {
        my %m = ();
        for my $k ( _uniq( keys %$lhs, keys %$rhs ) ) {
          my $npath = join '/', $path, $k;
          if ( my $r = $RULES{$npath} ) {
            $m{$k} = $r->( $self, $npath, $lhs->{$k}, $rhs->{$k} );
          }
          else {
            $m{$k} = $self->_merge( $npath, $lhs->{$k}, $rhs->{$k} );
          }
        }
        return \%m;
      }
      elsif ( 'ARRAY' eq $lr ) {
        my $npath = join '/', $path, '*';
        if ( my $r = $RULES{$npath} ) {
          return $r->( $self, $npath, $lhs, $rhs );
        }
        return [ _uniq( @$lhs, @$rhs ) ];
      }
      else {
        croak "Unknown type: $lr";
      }
    }

    # Scalars
    if ( my $r = $RULES{$path} ) {
      return $r->( $self, $path, $lhs, $rhs );
    }

    croak "Scalar mismatch with no merge rule"
     unless $lhs eq $rhs;

    return $lhs;
  }
}
1;

# vim:ts=2:sw=2:sts=2:et:ft=perl
