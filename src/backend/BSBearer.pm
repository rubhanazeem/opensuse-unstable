#
# Copyright (c) 2018 SUSE Inc.
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
# Bearer authentification
#

package BSBearer;

use BSRPC ':https';
use BSHTTP;
use MIME::Base64;

use strict;

sub decode_reply {
  my ($state, $json) = @_;
  my $reply = JSON::XS::decode_json($json);
  my $token = $reply->{'token'} || $reply->{'access_token'};
  die("bearer auth rpc did not return a token\n") unless $token;
  return $state->{'auth'} = "Bearer $token";
}

sub authenticator_function {
  my ($state, $param, $wwwauthenticate) = @_; 
  return $state->{'auth'} if !$wwwauthenticate;		# return last auth
  delete $state->{'auth'};
  my $creds = $state->{'creds'};
  my $auth;
  my %auth = BSHTTP::parseauthenticate($wwwauthenticate);
  if ($auth{'basic'} && defined($creds)) {
    $auth = 'Basic '.MIME::Base64::encode_base64($creds, '');
    $state->{'auth'} = $auth;
  } elsif ($auth{'bearer'}) {
    my $bearer = $auth{'bearer'};
    my $realm = ($bearer->{'realm'} || [])->[0];
    return '' unless $realm && $realm =~ /^https?:\/\//i;
    my @args = BSRPC::args($bearer, 'service', 'scope');
    print "requesting bearer auth from $realm [@args]\n" if $state->{'verbose'};
    my $bparam = { 'uri' => $realm };
    push @{$bparam->{'headers'}}, 'Authorization: Basic '.MIME::Base64::encode_base64($creds, '') if defined($creds);
    my $rpc = $state->{'rpccall'} || \&BSRPC::rpc;
    my $decoder = sub {decode_reply($state, $_[0])};
    eval { $auth = $rpc->($bparam, $decoder, @args) };
    return undef unless defined $auth;		# in progress
    warn($@) if $@; 
  }
  return $auth || '';
}

sub generate_authenticator {
  my ($creds, %opts) = @_;
  my $state = { %opts };
  $state->{'creds'} = $creds if defined $creds;
  return sub { authenticator_function($state, @_) };
}

sub get_credentials {
  my ($creds) = @_;
  if ($creds && $creds eq '-') {
    $creds = <STDIN>;
    chomp $creds;
  }
  return $creds;
}

1;
