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
# Run a HTTP query operation. Single thread only.
#

package BSRPC;

use Socket;
use POSIX;
use XML::Structured;
use Symbol;
use MIME::Base64;

use BSHTTP;

use strict;

our $useragent = 'BSRPC 0.9.1';
our $noproxy;
our $logtimeout;
our $autoheaders;

my %hostlookupcache;
my %cookiestore;	# our session store to keep iChain fast
my $tossl;

sub import {
  if (grep {$_ eq ':https'} @_) {
    require BSSSL;
    $tossl = \&BSSSL::tossl;
  }
}


my $tcpproto = getprotobyname('tcp');

sub urlencode {
  return BSHTTP::urlencode($_[0]);
}

sub createuri {
  my ($param, @args) = @_;
  my $uri = $param->{'uri'};
  if (!$param->{'verbatim_uri'}) {
    # encode uri, but do not encode the host part
    if ($uri =~ /^(https?:\/\/[^\/]*\/)(.*)$/s) {
      $uri = $1; 
      $uri .= BSHTTP::urlencode($2);
    } else {
      $uri = BSHTTP::urlencode($uri);
    }
  }
  $uri .= (($uri =~ /\?/) ? '&' : '?') . BSHTTP::queryencode(@args) if @args;
  $uri .= "#".BSHTTP::urlencode($param->{'fragment'}) if defined $param->{'fragment'};
  return $uri;
}

sub useproxy {
  my ($param, $host) = @_;

  my $nop = $noproxy;
  if (!defined($nop)) {
    # XXX: should not get stuff from BSConfig, but compatibility...
    $nop = $BSConfig::noproxy if defined($BSConfig::noproxy);
  }
  return 1 if !defined $nop;
  # strip leading and tailing whitespace
  $nop =~ s/^\s+//;
  $nop =~ s/\s+$//;
  # noproxy is a list separated by commas and optional whitespace
  for (split(/\s*,\s*/, $nop)) {
    s/^\.?/./s; 
    return 0 if ".$host" =~ /\Q$_\E$/s;
  }
  return 1;
}

sub addautoheaders {
  my ($hdrs, $aheaders) = @_;
  for (@{$aheaders || $autoheaders || []}) {
    my $k = (split(':', $_, 2))[0];
    push @$hdrs, $_ unless grep {/^\Q$k\E:/i} @$hdrs;
  }
}

sub createreq {
  my ($param, $uri, $proxy, $cookiestore, @xhdrs) = @_;

  my $act = $param->{'request'} || 'GET';
  if (exists($param->{'socket'})) {
    my $req = "$act $uri HTTP/1.1\r\n".join("\r\n", @xhdrs)."\r\n\r\n";
    return ('', undef, undef, $req, undef);
  }
  my ($proxyauth, $proxytunnel);
  die("bad uri: $uri\n") unless $uri =~ /^(https?):\/\/(?:([^\/\@]*)\@)?([^\/:]+)(:\d+)?(\/.*)$/;
  my ($proto, $auth, $host, $port, $path) = ($1, $2, $3, $4, $5);
  my $hostport = $port ? "$host$port" : $host;
  undef $proxy if $proxy && !useproxy($param, $host);
  if ($proxy) {
    die("bad proxy uri: $proxy\n") unless "$proxy/" =~ /^(https?):\/\/(?:([^\/\@]*)\@)?([^\/:]+)(:\d+)?(\/.*)$/;
    ($proto, $proxyauth, $host, $port) = ($1, $2, $3, $4);
    $path = $uri unless $uri =~ /^https:/;
  }
  $port = substr($port || ($proto eq 'http' ? ":80" : ":443"), 1);
  if ($param->{'_stripauthhost'} && $host ne $param->{'_stripauthhost'}) {
    @xhdrs = grep {!/^authorization:/i} @xhdrs;
    delete $param->{'authenticator'};
  }
  unshift @xhdrs, "Connection: close" unless $param->{'noclose'};
  unshift @xhdrs, "User-Agent: $useragent" unless !defined($useragent) || grep {/^user-agent:/si} @xhdrs;
  unshift @xhdrs, "Host: $hostport" unless grep {/^host:/si} @xhdrs;
  if (defined $auth) {
    $auth =~ s/%([a-fA-F0-9]{2})/chr(hex($1))/ge;
    unshift @xhdrs, "Authorization: Basic ".encode_base64($auth, '');
  }
  if (defined $proxyauth) {
    $proxyauth =~ s/%([a-fA-F0-9]{2})/chr(hex($1))/ge;
    unshift @xhdrs, "Proxy-Authorization: Basic ".encode_base64($proxyauth, '');
  }
  if ($proxy && $uri =~ /^https/) {
    if ($hostport =~ /:\d+$/) {
      $proxytunnel = "CONNECT $hostport HTTP/1.1\r\nHost: $hostport\r\n";
    } else {
      $proxytunnel = "CONNECT $hostport:443 HTTP/1.1\r\nHost: $hostport:443\r\n";
    }
    $proxytunnel .= shift(@xhdrs)."\r\n" if defined $proxyauth;
    $proxytunnel .= "\r\n";
  }
  if ($cookiestore && %$cookiestore) {
    if ($uri =~ /((:?https?):\/\/(?:([^\/]*)\@)?(?:[^\/:]+)(?::\d+)?)(?:\/.*)$/) {
      push @xhdrs, map {"Cookie: $_"} @{$cookiestore->{$1} || []};
    }
  }
  my $req = "$act $path HTTP/1.1\r\n".join("\r\n", @xhdrs)."\r\n\r\n";
  return ($proto, $host, $port, $req, $proxytunnel);
}

sub updatecookies {
  my ($cookiestore, $uri, $setcookie) = @_;
  return unless $cookiestore && $uri && $setcookie;
  my @cookie = split(',', $setcookie);
  s/;.*// for @cookie;
  if ($uri =~ /((:?https?):\/\/(?:([^\/]*)\@)?(?:[^\/:]+)(?::\d+)?)(?:\/.*)$/) {
    my %cookie = map {$_ => 1} @cookie;
    push @cookie, grep {!$cookie{$_}} @{$cookiestore->{$1} || []};
    splice(@cookie, 10) if @cookie > 10;
    $cookiestore->{$1} = \@cookie;
  }
}

sub args {
  my ($h, @k) = @_;
  return map {
    my ($v, $k) = ($h->{$_}, $_);
    !defined($v) ? () : ref($v) eq 'ARRAY' ? map {"$k=$_"} @$v : "$k=$v";
  } @k;
}

sub readanswerheaderblock {
  my ($sock, $ans) = @_;
  $ans = '' unless defined $ans;
  do {
    my $r = sysread($sock, $ans, 1024, length($ans));
    if (!$r) {
      die("received truncated answer: $!\n") if !defined($r) && $! != POSIX::EINTR && $! != POSIX::EWOULDBLOCK;
      die("received truncated answer\n") if defined $r;
    }
  } while ($ans !~ /\n\r?\n/s);
  die("bad HTTP answer\n") unless $ans =~ s/^HTTP\/\d+?\.\d+?\s+?(\d+[^\r\n]*)/Status: $1/s;
  return ($1, $ans);
}

sub lookuphost {
  my ($host, $cache) = @_;
  return $cache->{$host}->[0] if $cache && $cache->{$host} && $cache->{$host}->[1] > time();
  my $hostaddr = inet_aton($host);
  return undef unless $hostaddr;
  $cache->{$host} = [ $hostaddr, time() + 24 * 3600 ] if $cache;
  return $hostaddr;
}

#
# handled paramters:
# timeout
# uri
# data
# datafmt
# headers (array)
# chunked
# request
# verbatim_uri
# socket
# https
# continuation
# verbose
# sender
# async
# replyheaders
# receiver
# ignorestatus
# receiverarg
# maxredirects
# proxy
# formurlencode
#

sub rpc {
  my ($param, $xmlargs, @args) = @_;

  $param = {'uri' => $param} if ref($param) ne 'HASH';

  # process timeout setup
  if ($param->{'timeout'}) {
    my %paramcopy = %$param;
    my $timeout = delete $paramcopy{'timeout'};
    $paramcopy{'running_timeout'} = $timeout;
    my $ans;
    local $SIG{'ALRM'} = sub {
      alarm(0);
      print "rpc timeout($timeout sec), uri: '$param->{uri}'\n" if $logtimeout;
      die("rpc timeout\n");
    };
    eval {
      eval {
        alarm($timeout);
        $ans = rpc(\%paramcopy, $xmlargs, @args);
      };
      alarm(0);
      die($@) if $@;
    };
    die($@) if $@;
    return $ans;
  }

  my @xhdrs = @{$param->{'headers'} || []};
  my $chunked = $param->{'chunked'} ? 1 : undef;

  # do data conversion
  my $data = $param->{'data'};
  if ($param->{'datafmt'} && defined($data)) {
    my $datafmt = $param->{'datafmt'};
    if (ref($datafmt) eq 'CODE') {
      $data = $datafmt->($data);
    } else {
      $data = XMLout($datafmt, $data);
    }
  }

  # do from urlencoding if requested
  my $formurlencode = $param->{'formurlencode'};
  if (!defined($data) && ($param->{'request'} || '') eq 'POST' && @args) {
    if (grep {/^content-type:\sapplication\/x-www-form-urlencoded$/i} @xhdrs) {
      $formurlencode = 1;		# compat
    } elsif ($formurlencode) {
      push @xhdrs, 'Content-Type: application/x-www-form-urlencoded';
    }
    if ($formurlencode) {
      $data = BSHTTP::queryencode(@args);
      @args = ();
    }
  }

  push @xhdrs, "Content-Length: ".length($data) if defined($data) && !ref($data) && !$chunked && !grep {/^content-length:/i} @xhdrs;
  push @xhdrs, "Transfer-Encoding: chunked" if $chunked;
  if ($param->{'authenticator'} && !grep {/^authorization:/i} @xhdrs) {
    # ask authenticator for cached authorization
    my $auth = $param->{'authenticator'}->($param);
    push @xhdrs, "Authorization: $auth" if $auth;
  }
  my $uri = createuri($param, @args);
  my $proxy = $param->{'proxy'};
  addautoheaders(\@xhdrs);
  my ($proto, $host, $port, $req, $proxytunnel) = createreq($param, $uri, $proxy, \%cookiestore, @xhdrs);
  if ($proto eq 'https' || $proxytunnel) {
    die("https not supported\n") unless $tossl || $param->{'https'};
  }

  # connect to server
  my $sock;
  if (exists($param->{'socket'})) {
    $sock = $param->{'socket'};
  } else {
    my $hostaddr = lookuphost($host, \%hostlookupcache);
    die("unknown host '$host'\n") unless $hostaddr;
    socket($sock, PF_INET, SOCK_STREAM, $tcpproto) || die("socket: $!\n");
    setsockopt($sock, SOL_SOCKET, SO_KEEPALIVE, pack("l",1));
    connect($sock, sockaddr_in($port, $hostaddr)) || die("connect to $host:$port: $!\n");
    if ($proxytunnel) {
      BSHTTP::swrite($sock, $proxytunnel);
      my ($status, $ans) = readanswerheaderblock($sock);
      die("proxy tunnel: CONNECT method failed: $status\n") unless $status =~ /^200[^\d]/;
    }
    if ($proto eq 'https' || $proxytunnel) {
      ($param->{'https'} || $tossl)->($sock, $param->{'ssl_keyfile'}, $param->{'ssl_certfile'}, 1, $host);
      if ($param->{'sslpeerfingerprint'}) {
	die("bad sslpeerfingerprint '$param->{'sslpeerfingerprint'}'\n") unless $param->{'sslpeerfingerprint'} =~ /^(.*?):(.*)$/s;
	my $pfp =  tied(*{$sock})->peerfingerprint($1);
	die("peer fingerprint does not match: $2 != $pfp\n") if $2 ne $pfp;
      }
    }
  }

  # send request
  if (!$param->{'continuation'}) {
    $data = '' unless defined $data;
    if ($param->{'verbose'}) {
      print "> $_\n" for split("\r\n", $req);
      #print "> $data\n" unless ref($data);
    }
    if (!ref($data)) {
      # append body to request (chunk encoded if requested)
      if ($chunked) {
	$data = sprintf("%X\r\n", length($data)).$data."\r\n" if $data ne '';
	$data .= "0\r\n\r\n";
      }
      $req .= $data;
      undef $data;
    }
    if ($param->{'sender'}) {
      $param->{'sender'}->($param, $sock, $req, $data);
    } elsif (!ref($data)) {
      BSHTTP::swrite($sock, $req);
    } else {
      BSHTTP::swrite($sock, $req);
      while(1) {
	$req = &$data($param, $sock);
	last if !defined($req) || !length($req);
        BSHTTP::swrite($sock, $req, $chunked);
      }
      BSHTTP::swrite($sock, "0\r\n\r\n") if $chunked;
    }
  }

  # return here if in async mode
  if ($param->{'async'} && !$param->{'continuation'}) {
    my $ret = {};
    $ret->{'uri'} = $uri;
    $ret->{'socket'} = $sock;
    $ret->{'async'} = 1;
    $ret->{'continuation'} = 1;
    $ret->{'request'} = $param->{'request'} || 'GET';
    $ret->{'verbose'} = $param->{'verbose'} if $param->{'verbose'};
    $ret->{'replyheaders'} = $param->{'replyheaders'} if $param->{'replyheaders'};
    $ret->{'receiver'} = $param->{'receiver'} if $param->{'receiver'};
    $ret->{'receiverarg'} = $xmlargs if $xmlargs;
    return $ret;
  }

  # read answer from server, first the header block
  my ($status, $ans) = readanswerheaderblock($sock);
  $ans =~ /^(.*?)\n\r?\n(.*)$/s;
  my $headers = $1;
  $ans = $2;
  if ($param->{'verbose'}) {
    print "< $_\n" for split(/\r?\n/, $headers);
  }
  my %headers;
  BSHTTP::gethead(\%headers, $headers);

  # process header
  #
  # HTTP Status Code Definitions
  # Successful 2xx
  # https://www.w3.org/Protocols/rfc2616/rfc2616-sec10.html
  #
  updatecookies(\%cookiestore, $param->{'uri'}, $headers{'set-cookie'}) if $headers{'set-cookie'};
  if ($status =~ /^2\d\d[^\d]/) {
    undef $status;
  } else {
    #if ($param->{'verbose'}) {
    #  1 while sysread($sock, $ans, 1024, length($ans));
    #  print "< $ans\n";
    #}
    if ($status =~ /^30[27][^\d]/ && ($param->{'ignorestatus'} || 0) != 2) {
      close $sock;
      die("error: no redirects allowed\n") unless defined $param->{'maxredirects'};
      die("error: status 302 but no 'location' header found\n") unless exists $headers{'location'};
      die("error: max number of redirects reached\n") if $param->{'maxredirects'} < 1;
      my %myparam = %$param;
      $myparam{'uri'} = $headers{'location'};
      $myparam{'maxredirects'} = $param->{'maxredirects'} - 1;
      $myparam{'_stripauthhost'} = $host;	# strip authentication on redirect to different domain
      $myparam{'verbatim_uri'} = 1;
      return rpc(\%myparam, $xmlargs, @args);
    }
    if ($status =~ /^401[^\d]/ && $param->{'authenticator'} && $headers{'www-authenticate'}) {
      # unauthorized, ask callback for authorization
      my $auth = $param->{'authenticator'}->($param, $headers{'www-authenticate'}, \%headers);
      if ($auth) {
        close $sock;
        my %myparam = %$param;
        delete $myparam{'authenticator'};
        $myparam{'headers'} = [ grep {!/^authorization:/i} @{$myparam{'headers'} || []} ];
        push @{$myparam{'headers'}}, "Authorization: $auth";
        return rpc(\%myparam, $xmlargs, @args);
      }
    }
    if (!$param->{'ignorestatus'}) {
      close $sock;
      die("$1 remote error: $2 ($uri)\n") if $status =~ /^(\d+) +(.*?)$/;
      die("remote error: $status\n");
    }
  }
  ${$param->{'replyheaders'}} = \%headers if $param->{'replyheaders'};

  # read and process rest of answer
  my $ansreq = {
    'headers' => \%headers,
    'rawheaders' => $headers,
    '__socket' => $sock,
    '__data' => $ans,
  };
  if (($param->{'request'} || 'GET') eq 'HEAD') {
    close $sock;
    undef $sock;
    return \%headers unless $param->{'receiver'};
    delete $ansreq->{'__socket'};
    delete $ansreq->{'__data'};
    $ansreq->{'__cl'} = -1;	# eof
  }
  my $receiver = $param->{'receiver'};
  $xmlargs ||= $param->{'receiverarg'};
  if ($receiver) {
    $ans = $receiver->($ansreq, $param, $xmlargs);
    $xmlargs = undef;
  } else {
    $ans = BSHTTP::read_data($ansreq, undef, 1);
  }
  close $sock if $sock;

  #if ($param->{'verbose'}) {
  #  print "< $ans\n";
  #}
  if ($xmlargs) {
    if (ref($xmlargs) eq 'CODE') {
      $ans = $xmlargs->($ans);
    } else {
      die("answer is not xml\n") if $ans !~ /<.*?>/s;
      $ans = XMLin($xmlargs, $ans);
    }
  }
  return $ans;
}

1;
