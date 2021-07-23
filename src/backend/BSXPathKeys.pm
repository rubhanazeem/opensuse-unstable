#
# Copyright (c) 2006, 2007 Michael Schroeder, Novell Inc.
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License version 2 as
# published by the Free Software Foundation.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program (see the file COPYING); if not, write to the
# Free Software Foundation, Inc.,
# 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301, USA
#
################################################################
#
# Abstract data implementation for the BSXPath engine. Data is
# identified via keys.
#


package BSXPathKeys;

use BSXPath;
use Data::Dumper;

use strict;

#
# needs:
#   db->values($path)       -> array of values;
#   db->keys($path, $value) -> array of keys;
#   db->fetch($key)         -> data;
#
# also used if available:
#   db->{"fetch_$key"}      super-fast select_path_from_key function
#   db->{'noindex'}->{$path}
#   db->{'noindexdatall'}
#   db->{'indexfunc'}
#


#
# node types:
#
# value defined
#     -> concrete node element
#        keys/other must also be set, define value set
#
# keys defined
#     -> abstract node element
#        limited to keys
#
# all other
#     -> abstract node element, unlimited
#




sub node {
  my ($db, $path, $limit) = @_;
  my $v = bless {};
  $v->{'db'} = $db;
  $v->{'path'} = $path;
  $v->{'limit'} = $limit;
  return $v;
}

sub selectpath {
  my ($v, $path) = @_;
  $v = [ $v ] unless ref($v) eq 'ARRAY';
  my @v = @$v;
  my $c;
  while(1) {
    last if !defined($path) || $path eq '';
    ($c, $path) = split('/', $path, 2);
    for my $vv (splice(@v)) {
      next unless ref($vv) eq 'HASH';
      $vv = $vv->{$c};
      next unless defined($vv);
      push @v, ref($vv) eq 'ARRAY' ? @$vv : $vv;
    }
  }
  return @v;
}

sub value {
  my ($self) = @_;
  my @v;
  if (exists($self->{'value'})) {
    return [ $self->{'value'} ];	# hmm, what about other?
  }
  my $db = $self->{'db'};
  my $path = $self->{'path'};
  if (!exists($self->{'keys'})) {
    if (defined($path)) {
      push @v, $db->values($path);
    } else {
      push @v, $db->keys();
    }
  } else {
    die("413 search limit reached\n") if $self->{'limit'} && @{$self->{'keys'}} > $self->{'limit'} && !$db->{'cheapfetch'};
    for my $k (@{$self->{'keys'}}) {
      my $v = $db->fetch($k);
      next unless defined $v;
      push @v, selectpath($v, $path);
    }
    return \@v;
  }
  die("413 search limit reached\n") if $self->{'limit'} && @v > $self->{'limit'};
  return \@v;
}

sub step {
  my ($self, $c) = @_;
  return [] if exists $self->{'value'};	# can't step concrete value
  my $v = bless {};
  $v->{'db'} = $self->{'db'};
  $v->{'keys'} = $self->{'keys'} if $self->{'keys'};
  $v->{'limit'} = $self->{'limit'} if $self->{'limit'};
  if ($self->{'path'} eq '') {
    $v->{'path'} = "$c";
  } else {
    $v->{'path'} = "$self->{'path'}/$c";
  }
  return $v;
}

sub toconcrete {
  my ($self) = @_;
  my $vv = bless {};
  $vv->{'db'} = $self->{'db'};
  $vv->{'limit'} = $self->{'limit'} if $self->{'limit'};
  if ($self->{'keys'}) {
    $vv->{'keys'} = $self->{'keys'};
    $vv->{'value'} = 'true';
    $vv->{'other'} = '';
  } else {
    $vv->{'keys'} = [];
    $vv->{'value'} = '';
    $vv->{'other'} = 'true';
  }
  return $vv;
}

sub boolop_not_helper {$_[0]};

sub boolop {
  my ($self, $v1, $v2, $op, $negpol, $hint) = @_;
  if (ref($v1) ne ref($self) && ref($v2) ne ref($self)) {
    return $op->($v1, $v2) ? 'true' : '';
  }
  #print "boolop ".Dumper($v1).Dumper($v2)."---\n";
  #print "negated!\n" if $negpol;
  if (ref($v1) eq ref($self) && ref($v2) eq ref($self)) {
    $v1 = toconcrete($v1) unless exists $v1->{'value'};
    $v2 = toconcrete($v2) unless exists $v2->{'value'};
    my $v = bless {};
    $v->{'db'} = $v1->{'db'};
    $v->{'limit'} = $v1->{'limit'} if $v1->{'limit'};
    my @k;
    my %k1 = map {$_ => 1} @{$v1->{'keys'}};
    my %k2 = map {$_ => 1} @{$v2->{'keys'}};
    if ($op->($v1->{'other'}, $v2->{'other'})) {
      push @k, grep {$k2{$_}} @{$v1->{'keys'}} if !$op->($v1->{'value'}, $v2->{'value'});
      push @k, grep {!$k2{$_}} @{$v1->{'keys'}} if !$op->($v1->{'value'}, $v2->{'other'});
      push @k, grep {!$k1{$_}} @{$v2->{'keys'}} if !$op->($v1->{'other'}, $v2->{'value'});
      $v->{'value'} = '';
      $v->{'other'} = 'true';
    } else {
      push @k, grep {$k2{$_}} @{$v1->{'keys'}} if $op->($v1->{'value'}, $v2->{'value'});
      push @k, grep {!$k2{$_}} @{$v1->{'keys'}} if $op->($v1->{'value'}, $v2->{'other'});
      push @k, grep {!$k1{$_}} @{$v2->{'keys'}} if $op->($v1->{'other'}, $v2->{'value'});
      $v->{'value'} = 'true';
      $v->{'other'} = '';
    }
    $v->{'keys'} = \@k;
    return $v;
  }
  if (ref($v1) eq ref($self)) {
    my $v = bless {};
    $v->{'db'} = $v1->{'db'};
    $v->{'limit'} = $v1->{'limit'} if $v1->{'limit'};
    my $db = $v1->{'db'};
    if (exists($v1->{'value'})) {
      $v->{'keys'} = $v1->{'keys'};
      $v->{'value'} = $op->($v1->{'value'}, $v2) ? 'true' : '';
      $v->{'other'} = $op->($v1->{'other'}, $v2) ? 'true' : '';
      return $v;
    }
    if ($op == \&BSXPath::boolop_not) {
      $op = \&boolop_not_helper;	# convert not op to boolean op
      $negpol = !$negpol;
    }
    my @k;
    my %k = map {$_ => 1} @{$v1->{'keys'} || []};
    if ($v1->{'keys'} && !@{$v1->{'keys'}}) {
      @k = ();
    } elsif ($v1->{'keys'} && $v1->{'path'} && $db->{"fetch_$v1->{'path'}"}) {
      # have super-fast select_path_from_key function
      # optimize boolop_eq because it is so common
      if ($op == \&BSXPath::boolop_eq && !$negpol) {
        for my $k (@{$v1->{'keys'}}) {
          push @k, $k if grep {$_ eq $v2} $db->{"fetch_$v1->{'path'}"}->($db, $k);
        }
      } else {
	for my $k (@{$v1->{'keys'}}) {
	  my $r = grep {$op->($_, $v2)} $db->{"fetch_$v1->{'path'}"}->($db, $k);
	  push @k, $k if $negpol ? !$r : $r;
	}
      }
    } elsif ($op == \&BSXPath::boolop_eq) {
      @k = $db->keys($v1->{'path'}, $v2, $v1->{'keys'});
      @k = grep {$k{$_}} @k if $v1->{'keys'};
      #die("413 search limit reached\n") if $v1->{'limit'} && @k > $v1->{'limit'};
      $negpol = 0;
    } else {
      my $noindex = $db->{'noindexatall'} && !($db->{'indexfunc'} && $db->{'indexfunc'}->{$v1->{'path'}}) ? 1 : 0;
      $noindex = 1 if $db->{'noindex'} && $db->{'noindex'}->{$v1->{'path'}};
      $noindex = 1 if !$v1->{'keys'} && $op == \&boolop_not_helper;
      my @values;
      if (!$noindex) {
        for my $vv ($db->values($v1->{'path'}, $v1->{'keys'}, $hint, $v2)) {
	  push @values, $vv if $negpol ? !$op->($vv, $v2) : $op->($vv, $v2);
	}
      }
      if ($noindex || ($v1->{'keys'} && @values > @{$v1->{'keys'}})) {
	my $keys = $v1->{'keys'} || [ $db->keys() ];
	die("413 search limit reached\n") if !$db->{'cheapfetch'} && $v1->{'limit'} && @$keys > $v1->{'limit'};
	for my $k (@$keys) {
	  my $vv = $db->fetch($k);
	  next unless defined $vv;
	  my $r = grep {$op->($_, $v2)} selectpath($vv, $v1->{'path'});
	  push @k, $k if $negpol ? !$r : $r;
	}
      } else {
	for my $vv (@values) {
	  if ($v1->{'keys'}) {
	    push @k, grep {$k{$_}} $db->keys($v1->{'path'}, $vv, $v1->{'keys'});
	  } else {
	    push @k, $db->keys($v1->{'path'}, $vv, $v1->{'keys'});
	  }
	  die("413 search limit reached\n") if $v1->{'limit'} && @k > $v1->{'limit'};
	}
      }
    }
    $negpol = !$negpol if $op == \&boolop_not_helper;	# back to original value
    $v->{'keys'} = \@k;
    $v->{'value'} = $negpol ? '' : 'true';
    $v->{'other'} = $negpol ? 'true' : '';
    #print "==> ".Dumper($v)."<===\n";
    return $v;
  }
  if (ref($v2) eq ref($self)) {
    my $v = bless {};
    $v->{'db'} = $v1->{'db'};
    $v->{'limit'} = $v1->{'limit'} if $v1->{'limit'};
    my $db = $v1->{'db'};
    if (exists($v2->{'value'})) {
      $v->{'keys'} = $v2->{'keys'};
      $v->{'value'} = $op->($v1, $v2->{'value'}) ? 'true' : '';
      $v->{'other'} = $op->($v1, $v2->{'other'}) ? 'true' : '';
      return $v;
    }
    my @k;
    my %k = map {$_ => 1} @{$v2->{'keys'} || []};
    if ($v2->{'keys'} && !@{$v2->{'keys'}}) {
      @k = ();
    } elsif ($v2->{'keys'} && $v2->{'path'} && $db->{"fetch_$v2->{'path'}"}) {
      # have super-fast select_path_from_key function
      # optimize boolop_eq because it is so common
      if ($op == \&BSXPath::boolop_eq && !$negpol) {
        for my $k (@{$v2->{'keys'}}) {
          push @k, $k if grep {$v1 eq $_} $db->{"fetch_$v2->{'path'}"}->($db, $k);
        }
      } else {
	for my $k (@{$v2->{'keys'}}) {
	  my $r = grep {$op->($v1, $_)} $db->{"fetch_$v2->{'path'}"}->($db, $k);
	  push @k, $k if $negpol ? !$r : $r;
	}
      }
    } elsif ($op == \&BSXPath::boolop_eq) {
      @k = $db->keys($v2->{'path'}, $v1, $v2->{'keys'});
      @k = grep {$k{$_}} @k if $v2->{'keys'};
      #die("413 search limit reached\n") if $v2->{'limit'} && @k > $v2->{'limit'};
      $negpol = 0;
    } else {
      my $noindex = $db->{'noindexatall'} && !($db->{'indexfunc'} && $db->{'indexfunc'}->{$v2->{'path'}}) ? 1 : 0;
      $noindex = 1 if $db->{'noindex'} && $db->{'noindex'}->{$v2->{'path'}};
      my @values;
      if (!$noindex) {
        for my $vv ($db->values($v2->{'path'}, $v2->{'keys'}, $hint, $v1)) {
	  push @values, $vv if $negpol ? !$op->($v1, $vv) : $op->($v1, $vv);
	}
      }
      if ($noindex || ($v2->{'keys'} && @values > @{$v2->{'keys'}})) {
	my $keys = $v2->{'keys'} || [ $db->keys() ];
	die("413 search limit reached\n") if !$db->{'cheapfetch'} && $v2->{'limit'} && @$keys > $v2->{'limit'};
	for my $k (@$keys) {
	  my $vv = $db->fetch($k);
	  next unless defined $vv;
	  my $r = grep {$op->($v1, $_)} selectpath($vv, $v2->{'path'});
	  push @k, $k if $negpol ? !$r : $r;
	}
      } else {
	for my $vv (@values) {
	  if ($v2->{'keys'}) {
	    push @k, grep {$k{$_}} $db->keys($v2->{'path'}, $vv, $v2->{'keys'});
	  } else {
	    push @k, $db->keys($v2->{'path'}, $vv, $v2->{'keys'});
	  }
	  die("413 search limit reached\n") if $v2->{'limit'} && @k > $v2->{'limit'};
	}
      }
    }
    $v->{'keys'} = \@k;
    $v->{'value'} = $negpol ? '' : 'true';
    $v->{'other'} = $negpol ? 'true' : '';
    return $v;
  }
}

sub predicate {
  my ($self, $v, $expr) = @_;
  if (ref($v) ne ref($self)) {
    $v = @$v ? 'true' : '' if ref($v) eq 'ARRAY';
    if ($v =~ /^-?\d+$/) {
      die("enumeration not implemented for abstract elements\n");
    } else {
      return $v ? $self : [];
    }
  }
  $v = toconcrete($v) unless exists $v->{'value'};
  my $vv = bless {};
  $vv->{'db'} = $self->{'db'};
  $vv->{'path'} = $self->{'path'};
  $vv->{'limit'} = $self->{'limit'} if $self->{'limit'};
  my @k;
  if ($v->{'value'}) {
    @k = @{$v->{'keys'}};
  } elsif ($v->{'other'}) {
    my %k = map {$_ => 1} @{$v->{'keys'}};
    @k = grep {!$k{$_}} $self->{'db'}->keys();
  }
  if (@k && $self->{'keys'}) {
    my %k = map {$_ => 1} @{$self->{'keys'}};
    @k = grep {$k{$_}} @k;
  }
  if ($self->{'path'}) {
    # postprocess matched keys
    for my $k (splice(@k)) {
      my $db = $self->{'db'};
      my $kv = $db->fetch($k);
      next unless $kv;
      $kv = [ selectpath($kv, $self->{'path'}) ];
      next unless @$kv;
      ($kv, undef) = BSXPath::predicate([[$kv, $kv, 1, 1]], $expr, [$kv]);
      push @k, $k if @{$kv->[0]};
    }
  }
  $vv->{'keys'} = \@k;
  return $vv;
}

sub keymatch {
  my ($self, $expr) = @_;
  my $v;
  ($v, $expr) = BSXPath::predicate([[$self, $self, 1, 1]], $expr, [$self]);
  die("junk at and of expr: $expr\n") if $expr ne '';
  return $v->[0]->{'keys'} || [];
}

sub limit {
  my ($self, $v) = @_;
  if (ref($v) ne ref($self)) {
    return $self;
  }
  return $self if $self->{'value'};
  if ($v->{'value'}) {
    my @k = @{$v->{'keys'}};
    my $vv = bless {};
    $vv->{'db'} = $self->{'db'};
    $vv->{'limit'} = $self->{'limit'} if $self->{'limit'};
    $vv->{'path'} = $self->{'path'};
    if (@k && $self->{'keys'}) {
      my %k = map {$_ => 1} @{$self->{'keys'}};
      @k = grep {$k{$_}} @k;
    }
    $vv->{'keys'} = \@k;
    return $vv;
  } else {
    return $self;
  }
}

1;
