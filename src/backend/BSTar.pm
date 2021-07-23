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
# Tar file accessing
#

package BSTar;

use strict;

my @headnames = qw{name mode uid gid size mtime chksum tartype linkname magic version uname gname major minor};

# tartype: 0=file 1=hardlink 2=symlink 3=char 4=block 5=dir 6=fifo

sub parsetarhead {
  my ($tarhead) = @_;
  my @head = unpack('A100A8A8A8A12A12A8a1A100a6a2A32A32A8A8A155x12', $tarhead);
  /^([^\0]*)/s && ($_ = $1) for @head;
  $head[7] = '0' if $head[7] eq '';	# map old \0 type to 0
  $head[$_] = oct($head[$_]) for (1, 2, 3, 5, 6, 13, 14);
  my $pad;
  if (substr($tarhead, 124, 1) eq "\x80") {
    # not octal, but binary!
    my @s = unpack('aCSNN', substr($tarhead, 124, 12));
    $head[4] = $s[4] + (2 ** 32) * $s[3] + (2 ** 64) * $s[2];
    $pad = (512 - ($s[4] & 511)) & 511;
  } else {
    $head[4] = oct($head[4]);
    $pad = (512 - ($head[4] & 511)) & 511;
  }
  $head[7] = '0' if $head[7] eq '' || $head[7] =~ /\W/;
  $head[7] = '5' if $head[7] eq '0' && $head[0] =~ /\/$/s;	# dir
  if ($head[9] eq 'ustar' && $head[15] ne '') {		# ustar prefix handling
    $head[15] =~ s/\/$//s;
    $head[0] = "$head[15]/$head[0]";
  }
  my $ent = { map {$headnames[$_] => $head[$_]} (0..$#headnames) };
  return ($ent, $head[4], $pad);
}

sub parseoverride {
  my ($override, $tartype, $data) = @_;
  $override ||= {};
  if ($tartype eq 'L') {
    $override->{'name'} = $data;
  } elsif ($tartype eq 'K') {
    $override->{'linkname'} = $data;
  } elsif ($tartype eq 'x' || $tartype eq 'X') {
    $override->{'ispax'} = 1;
    while ($data =~ /^(\d+) / && $1 > 3) {
      my $entry = substr($data, length($1) + 1, $1 - length($1) - 2);	# -2 because of space and newline
      $data = substr($data, $1);
      $override->{'name'} = substr($entry, 5) if substr($entry, 0, 5) eq 'path=';
      $override->{'linkname'} = substr($entry, 9) if substr($entry, 0, 9) eq 'linkpath=';
    }
  }
  return $override;
}

sub list {
  my ($handle) = @_;

  my $offset = 0;
  my $override;
  my @tar;

  while (1) {
    my $head = '';
    last unless (read($handle, $head, 512) || 0) == 512;
    $offset += 512;
    last if $head eq "\0" x 512;
    next if substr($head, 500, 12) ne "\0" x 12;
    my ($ent, $size, $pad) = parsetarhead($head);
    my $bsize = $size + $pad;
    my $tartype = $ent->{'tartype'};
    next if $tartype eq 'V';	# ignore volume lables
    if ($tartype eq 'L' || $tartype eq 'K' || $tartype eq 'x' || $tartype eq 'X') {
      # read longname/longlink/pax extension
      last if $bsize < 1 || $bsize >= 1024 * 1024;
      my $data = '';
      last unless (read($handle, $data, $bsize) || 0) == $bsize;
      $offset += $bsize;
      substr($data, $size) = '';
      $override = parseoverride($override, $tartype, $data);
      next;
    }
    if ($override) {
      $ent->{$_} = $override->{$_} for keys %$override;
      undef $override;
    }
    $bsize = 0 if $tartype eq '2' || $tartype eq '3' || $tartype eq '4' || $tartype eq '6';
    $bsize = 0 if $tartype eq '1' && !$ent->{'ispax'};	# hard link magic
    $ent->{'offset'} = $offset if $tartype eq '0';
    if ($bsize) {
      last unless seek($handle, $bsize, 1);	# try to skip if seek fails?
      $offset += $bsize;
    }
    push @tar, $ent;
  }
  return \@tar;
}

sub extract {
  my ($handle, $ent, $offset, $length) = @_;
  die("cannot extract this type of entry\n") if defined($ent->{'tartype'}) && $ent->{'tartype'} ne '0';
  return '' if defined($length) && $length <= 0;
  $offset = 0 unless defined($offset) && $offset >= 0;
  if (exists $ent->{'data'}) {
    return substr($ent->{'data'}, $offset) unless defined $length;
    return substr($ent->{'data'}, $offset, $length);
  }
  my $size = $ent->{'size'};
  return '' if $offset >= $size;
  $length = $size - $offset if !defined($length) || $length > $size - $offset;
  die("cannot seek to $ent->{name} entry\n") unless seek($handle, $ent->{'offset'} + $offset, 0);
  my $data = '';
  die("cannot read $ent->{name} entry\n") unless (read($handle, $data, $length) || 0) == $length;
  return $data;
}

sub maketarhead {
  my ($file, $s) = @_; 

  my $h = "\0\0\0\0\0\0\0\0" x 64;
  my $pad = '';
  return ("$h$h") unless $file;
  my $name = $file->{'name'};
  my $linkname = $file->{'linkname'};
  my $tartype = $file->{'tartype'};
  if (!defined($tartype)) {
    $tartype = '0';
    $tartype = '5' if (($file->{'mode'} || 0) | 0xfff) == 0x4fff;
  }
  $name =~ s/\/?$/\// if $tartype eq '5';
  # XXX: add a pax header instead of dying
  die("maketarhead: name too big\n") if length($name) > 100;
  die("maketarhead: linkname too big\n") if defined($linkname) && length($linkname) > 100;
  my $mode = sprintf("%07o", $file->{'mode'} || 0x81a4);
  my $size = sprintf("%011o", $s->[7]);
  my $mtime = sprintf("%011o", defined($file->{'mtime'}) ? $file->{'mtime'} : $s->[9]);
  substr($h, 0, length($name), $name);
  substr($h, 100, length($mode), $mode);
  substr($h, 108, 15, "0000000\0000000000");	# uid/gid
  substr($h, 124, length($size), $size);
  substr($h, 136, length($mtime), $mtime);
  substr($h, 148, 8, '        ');
  substr($h, 156, 1, $tartype);
  substr($h, 157, length($linkname), $linkname) if defined($linkname);
  substr($h, 257, 8, "ustar\00000");		# magic/version
  substr($h, 329, 15, "0000000\0000000000");	# major/minor
  substr($h, 148, 7, sprintf("%06o\0", unpack("%16C*", $h)));
  $pad = "\0" x (512 - $s->[7] % 512) if $s->[7] % 512;
  return ($h, $pad);
}

sub writetar {
  my ($fd, $entries) = @_;

  my $writer;
  $writer = $fd if ref($fd) eq 'CODE';
  for my $ent (@{$entries || []}) {
    my (@s);
    my $f;
    if (exists $ent->{'file'}) {
      my $file = $ent->{'file'};
      if (ref($file)) {
        $f = $file;
      } else {
        @s = lstat($file);
        die("$file: $!\n") unless @s;
        if (-l _) {
          die("$file: is a symlink\n");
        } elsif (! -f _) {
          die("$file: not a plain file\n");
        }
        open($f, '<', $file) || die("$file: $!\n");
      }
      @s = stat($f);
      my $l = $s[7];
      if (defined($ent->{'offset'})) {
        die("$file: seek error: $!\n") unless defined(sysseek($f, $ent->{'offset'}, 0));
        $l -= $ent->{'offset'};
      }
      if (defined($ent->{'size'})) {
        die("$file: size too small for request\n") if $ent->{'size'} > $l;
        $l = $ent->{'size'};
      }
      $s[7] = $l;
      my $r = 0;
      my ($data, $pad) = maketarhead($ent, \@s);
      while(1) {
        $r = sysread($f, $data, $l > 8192 ? 8192 : $l, length($data)) if $l;
        die("$file: read error: $!\n") unless defined $r;
        die("$file: unexpected EOF\n") if $l && !$r;
        $data .= $pad if $r == $l;
        if ($writer) {
          $writer->($data);
        } else {
          print $fd $data or die("write error: $!\n");
        }
        $data = '';
        $l -= $r;
        last unless $l;
      }
      close $f unless ref $file;
    } else {
      $s[7] = length($ent->{'data'});
      $s[9] = $ent->{'mtime'} || time;
      my ($data, $pad) = maketarhead($ent, \@s);
      $data .= "$ent->{'data'}$pad";
      if ($writer) {
        $writer->($data);
      } else {
        print $fd $data or die("write error: $!\n");
      }
    }
  }
  my ($data) = maketarhead();
  if ($writer) {
    $writer->($data);
  } else {
    print $fd $data or die("write error: $!\n");
  }
}

sub writetarfile {
  my ($fn, $fnf, $tar, %opts) = @_;
  my $tarfd;
  open($tarfd, '>', $fn) || die("$fn: $!\n");
  writetar($tarfd, $tar);
  close($tarfd) || die("$fn close: $!\n");
  my $mtime = $opts{'mtime'};
  utime($mtime, $mtime, $fn) if defined $mtime;
  rename($fn, $fnf) || die("rename $fn $fnf: $!\n") if defined $fnf;
}

1;
