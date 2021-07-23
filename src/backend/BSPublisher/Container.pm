#
# Copyright (c) 2018 SUSE LLC
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
# Container handling of the publisher
#

package BSPublisher::Container;

use File::Temp qw/tempfile/;

use BSConfiguration;
use BSPublisher::Util;
use BSPublisher::Registry;
use BSUtil;
use BSTar;
use BSRepServer::Containerinfo;
use Build::Rpm;		# for verscmp_part

use strict;

my $uploaddir = "$BSConfig::bsdir/upload";

=head2 registries_for_prp - find registries for this project/repository
 
 Parameters:
  projid - published project
  repoid - published repository

 Returns:
  Array of registries

=cut

sub registries_for_prp {
  my ($projid, $repoid) = @_;
  return () unless $BSConfig::publish_containers && $BSConfig::container_registries;
  my @registries;
  my @s = @{$BSConfig::publish_containers};
  while (@s) {
    my ($k, $v) = splice(@s, 0, 2);
    if ("$projid/$repoid" =~ /^$k/ || $projid =~ /^$k/) {
      $v = [ $v ] unless ref $v;
      @registries = @$v;
      last;
    }
  }
  # convert registry names to configs
  for my $registry (BSUtil::unify(splice @registries)) {
    my $cr = $BSConfig::container_registries->{$registry};
    if (!$cr || (!$cr->{'server'} && !$cr->{'pushserver'})) {
      print "no valid registry config for '$registry'\n";
      next;
    }
    push @registries, { %$cr, '_name' => $registry };
  }
  return @registries;
}

sub have_good_project_signkey {
  my ($signargs) = @_;
  return 0 unless @{$signargs || []} >= 2;
  return 0 if $signargs->[0] ne '-P';
  return (-s $signargs->[1]) >= 10;
}

sub get_notary_pubkey {
  my ($projid, $pubkey, $signargs) = @_;

  my @signargs;
  push @signargs, '--project', $projid if $BSConfig::sign_project;
  push @signargs, '--signtype', 'notary' if $BSConfig::sign_type || $BSConfig::sign_type;
  push @signargs, @{$signargs || []};

  # ask the sign tool for the correct pubkey if we do not have a good sign key
  if ($BSConfig::sign_project && $BSConfig::sign && !have_good_project_signkey($signargs)) {
    local *S;
    open(S, '-|', $BSConfig::sign, @signargs, '-p') || die("$BSConfig::sign: $!\n");;
    $pubkey = '';
    1 while sysread(S, $pubkey, 4096, length($pubkey));
    if (!close(S)) {
      print "sign -p failed: $?\n";
      $pubkey = undef;
    }
  }

  # check pubkey
  die("could not determine pubkey for notary signing\n") unless $pubkey;
  my $pkalgo;
  eval { $pkalgo = BSPGP::pk2algo(BSPGP::unarmor($pubkey)) };
  if ($pkalgo && $pkalgo ne 'rsa') {
    print "public key algorithm is '$pkalgo', skipping notary upload\n";
    return (undef, undef);
  }
  # get rid of --project option
  splice(@signargs, 0, 2) if $BSConfig::sign_project;
  return ($pubkey, \@signargs);
}

=head2 default_container_mapper - map container data to registry repository/tags
 
=cut

sub default_container_mapper {
  my ($registry, $containerinfo, $projid, $repoid, $arch) = @_;

  my $repository_base = $registry->{repository_base} || '/';
  my $delimiter       = $registry->{repository_delimiter} || '/';
  $projid =~ s/:/$delimiter/g;
  $repoid =~ s/:/$delimiter/g;
  my $repository = lc("$repository_base$projid/$repoid");
  $repository =~ s/^\///;
  return map {"$repository/$_"} @{$containerinfo->{'tags'} || []};
}

sub calculate_container_state {
  my ($projid, $repoid, $containers, $multicontainer) = @_;
  my @registries = registries_for_prp($projid, $repoid);
  my $container_state = '';
  $container_state .= "//multi//" if $multicontainer;
  my @cs;
  for my $registry (@registries) {
    my $regname = $registry->{'_name'};
    my $mapper = $registry->{'mapper'} || \&default_container_mapper;
    for my $p (sort keys %$containers) {
      my $containerinfo = $containers->{$p};
      my $arch = $containerinfo->{'arch'};
      my @tags = $mapper->($registry, $containerinfo, $projid, $repoid, $arch);
      my $prefix = "$containerinfo->{'_id'}/$regname/$containerinfo->{'arch'}/";
      push @cs, map { "$prefix$_" } @tags;
    }
  }
  $container_state .= join('//', sort @cs);
  return $container_state;
}

=head2 cmp_containerinfo - compare the version/release of two containers
 
=cut

sub cmp_containerinfo {
  my ($containerinfo1, $containerinfo2) = @_;
  my $r;
  $r = Build::Rpm::verscmp_part($containerinfo1->{'version'} || '0', $containerinfo2->{'version'} || 0);
  return $r if $r;
  $r = Build::Rpm::verscmp_part($containerinfo1->{'release'} || '0', $containerinfo2->{'release'} || 0);
  return $r if $r;
  return 0;
}

=head2 upload_all_containers - upload found containers to the configured registries
 
=cut

sub upload_all_containers {
  my ($extrep, $projid, $repoid, $containers, $pubkey, $signargs, $multicontainer, $old_container_repositories) = @_;

  my $isdelete;
  if (!defined($containers)) {
    $isdelete = 1;
    $containers = {};
  } else {
    ($pubkey, $signargs) = get_notary_pubkey($projid, $pubkey, $signargs);
  }

  my $notary_uploads = {};
  my $have_some_trust;
  my @registries = registries_for_prp($projid, $repoid);

  my %allrefs;
  my %container_repositories;
  $old_container_repositories ||= {};
  for my $registry (@registries) {
    my $regname = $registry->{'_name'};
    my $registryserver = $registry->{pushserver} || $registry->{server};

    # collect uploads over all containers, decide which container to take
    # if there is a tag conflict
    my %uploads;
    my $mapper = $registry->{'mapper'} || \&default_container_mapper;
    for my $p (sort keys %$containers) {
      my $containerinfo = $containers->{$p};
      my $arch = $containerinfo->{'arch'};
      my $goarch = $containerinfo->{'goarch'};
      $goarch .= ":$containerinfo->{'govariant'}" if $containerinfo->{'govariant'};
      my @tags = $mapper->($registry, $containerinfo, $projid, $repoid, $arch);
      for my $tag (@tags) {
	my ($reponame, $repotag) = ($tag, 'latest');
	($reponame, $repotag) = ($1, $2) if $tag =~ /^(.*):([^:\/]+)$/;
	if ($uploads{$reponame}->{$repotag}->{$goarch}) {
	  my $otherinfo = $containers->{$uploads{$reponame}->{$repotag}->{$goarch}};
	  next if cmp_containerinfo($otherinfo, $containerinfo) > 0;
	}
	$uploads{$reponame}->{$repotag}->{$goarch} = $p;
      }
    }

    # ok, now go through every repository and upload all tags
    for my $repository (sort keys %uploads) {
      $container_repositories{$regname}->{$repository} = 1;

      my $uptags = $uploads{$repository};

      # do local publishing if requested
      if ($registryserver eq 'local:') {
	my $gun = $registry->{'notary_gunprefix'} || $registry->{'server'};
	undef $gun if $gun && $gun eq 'local:';
        if (defined($gun)) {
          $gun =~ s/^https?:\/\///;
	  $gun .= "/$repository";
	  undef $gun unless defined $pubkey;
	}
	$have_some_trust = 1 if $gun;
	do_local_uploads($extrep, $projid, $repoid, $repository, $gun, $containers, $pubkey, $signargs, $multicontainer, $uptags);
	my $pullserver = $registry->{'server'};
	undef $pullserver if $pullserver && $pullserver eq 'local:';
	if ($pullserver) {
	  $pullserver =~ s/https?:\/\///;
	  $pullserver =~ s/\/?$/\//;
	  for my $tag (sort keys %$uptags) {
	    my @p = sort(values %{$uptags->{$tag}});
	    push @{$allrefs{$_}}, "$pullserver$repository:$tag" for @p;
	  }
	}
	next;
      }

      # find common containerinfos so that we can push multiple tags in one go
      my %todo;
      my %todo_p;
      for my $tag (sort keys %$uptags) {
	my @p = sort(values %{$uptags->{$tag}});
	my $joinp = join('///', @p);
	push @{$todo{$joinp}}, $tag;
	$todo_p{$joinp} = \@p;
      }
      # now do the upload
      my $containerdigests = '';
      for my $joinp (sort keys %todo) {
	my @tags = @{$todo{$joinp}};
	my @containerinfos = map {$containers->{$_}} @{$todo_p{$joinp}};
	my ($digest, @refs) = upload_to_registry($registry, \@containerinfos, $repository, \@tags);
	add_notary_upload($notary_uploads, $registry, $repository, $digest, \@tags);
	$containerdigests .= $digest;
	push @{$allrefs{$_}}, @refs for @{$todo_p{$joinp}};
      }
      # all is pushed, now clean the rest
      delete_obsolete_tags_from_registry($registry, $repository, $containerdigests);
    }

    # delete repositories of former publish runs that are now empty
    for my $repository (@{$old_container_repositories->{$regname} || []}) {
      next if $uploads{$repository};
      if ($registryserver eq 'local:') {
        do_local_uploads($extrep, $projid, $repoid, $repository, undef, $containers, $pubkey, $signargs, $multicontainer, {});
	next;
      }
      my $containerdigests = '';
      add_notary_upload($notary_uploads, $registry, $repository, $containerdigests);
      delete_obsolete_tags_from_registry($registry, $repository, $containerdigests);
    }
  }
  $have_some_trust = 1 if %$notary_uploads;

  # postprocessing: write readme, create links
  my %allrefs_pp;
  my %allrefs_pp_lastp;
  for my $p (sort keys %$containers) {
    my $containerinfo = $containers->{$p};
    my $pp = $p;
    $pp =~ s/.*?\/// if $multicontainer;
    $allrefs_pp_lastp{$pp} = $p;	# for link creation
    push @{$allrefs_pp{$pp}}, @{$allrefs{$p} || []};	# collect all archs for the link
  }
  for my $pp (sort keys %allrefs_pp_lastp) {
    mkdir_p($extrep);
    unlink("$extrep/$pp.registry.txt");
    if (@{$allrefs_pp{$pp} || []}) {
      unlink("$extrep/$pp");
      # write readme file where to find the container
      my @r = sort(BSUtil::unify(@{$allrefs_pp{$pp}}));
      my $readme = "This container can be pulled via:\n";
      $readme .= "  docker pull $_\n" for @r;
      $readme .= "\nSet DOCKER_CONTENT_TRUST=1 to enable image tag verification.\n" if $have_some_trust;
      writestr("$extrep/$pp.registry.txt", undef, $readme);
    } elsif ($multicontainer && $allrefs_pp_lastp{$pp} ne $pp) {
      # create symlink to last arch
      unlink("$extrep/$pp");
      symlink("$allrefs_pp_lastp{$pp}", "$extrep/$pp");
    }
  }

  # do notary uploads
  if (%$notary_uploads) {
    if ($isdelete) {
      delete_from_notary($projid, $notary_uploads);
    } else {
      if (!defined($pubkey)) {
	print "skipping notary upload\n";
      } else {
        upload_to_notary($projid, $notary_uploads, $signargs, $pubkey);
      }
    }
  }

  # turn container repos into arrays and return
  $_ = [ sort keys %$_ ] for values %container_repositories;
  return \%container_repositories;
}

sub reconstruct_container {
  my ($containerinfo, $dst) = @_;
  my $manifest = $containerinfo->{'tar_manifest'};
  my $mtime = $containerinfo->{'tar_mtime'};
  my $blobids = $containerinfo->{'tar_blobids'};
  my $blobdir = $containerinfo->{'blobdir'};
  return unless $mtime && $manifest && $blobids && $blobdir;
  my @tar;
  for my $blobid (@$blobids) {
    my $file = "$blobdir/_blob.$blobid";
    die("missing blobid $blobid\n") unless -e $file;
    push @tar, {'name' => $blobid, 'file' => $file, 'mtime' => $mtime, 'offset' => 0, 'size' => (-s _)};
  }
  push @tar, {'name' => 'manifest.json', 'data' => $manifest, 'mtime' => $mtime, 'size' => length($manifest)};
  BSTar::writetarfile($dst, undef, \@tar, 'mtime' => $mtime);
}

=head2 upload_to_registry - upload containers

 Parameters:
  registry       - validated config for registry
  containerinfos - array of containers to upload (more than one for multiarch)
  repository     - registry repository name
  tags           - array of tags to upload to
  notary_uploads - hash to store notary information

 Returns:
  containerdigests + public references to uploaded containers

=cut

sub upload_to_registry {
  my ($registry, $containerinfos, $repository, $tags) = @_;

  return unless @{$containerinfos || []} && @{$tags || []};
  
  my $registryserver = $registry->{pushserver} || $registry->{server};
  my $pullserver = $registry->{server};
  $pullserver =~ s/https?:\/\///;
  $pullserver =~ s/\/?$/\//;
  $pullserver = '' if $pullserver =~ /docker.io\/$/;
  $repository = "library/$repository" if $pullserver eq '' && $repository !~ /\//;

  # decompress tar files
  my @tempfiles;
  my @uploadfiles;
  my $blobdir;
  for my $containerinfo (@$containerinfos) {
    my $file = $containerinfo->{'publishfile'};
    if (!defined($file)) {
      # tar file needs to be constructed from blobs
      $blobdir = $containerinfo->{'blobdir'};
      die("need a blobdir for containerinfo uploads\n") unless $blobdir;
      push @uploadfiles, "$blobdir/container.".scalar(@uploadfiles).".containerinfo";
      BSRepServer::Containerinfo::writecontainerinfo($uploadfiles[-1], undef, $containerinfo);
    } elsif ($file =~ /(.*)\.tgz$/ && ($containerinfo->{'type'} || '') eq 'helm') {
      my $helminfofile = "$1.helminfo";
      $blobdir = $containerinfo->{'blobdir'};
      die("need a blobdir for helminfo uploads\n") unless $blobdir;
      die("bad publishfile\n") unless $helminfofile =~ /^\Q$blobdir\E\//;	# just in case
      push @uploadfiles, $helminfofile;
      BSRepServer::Containerinfo::writecontainerinfo($uploadfiles[-1], undef, $containerinfo);
    } elsif ($file =~ /\.tar$/) {
      push @uploadfiles, $file;
    } else {
      my $tmpfile = decompress_container($file);
      push @uploadfiles, $tmpfile;
      push @tempfiles, $tmpfile;
    }
  }

  # do the upload
  mkdir_p($uploaddir);
  my $containerdigestfile = "$uploaddir/publisher.$$.containerdigests";
  unlink($containerdigestfile);
  my @opts = map {('-t', $_)} @$tags;
  push @opts, '-m' if @uploadfiles > 1;		# create multi arch container
  push @opts, '-B', $blobdir if $blobdir;
  my @cmd = ("$INC[0]/bs_regpush", '--dest-creds', '-', @opts, '-F', $containerdigestfile, $registryserver, $repository, @uploadfiles);
  print "Uploading to registry: @cmd\n";
  my $result = BSPublisher::Util::qsystem('echo', "$registry->{user}:$registry->{password}\n", 'stdout', '', @cmd);
  my $containerdigests = readstr($containerdigestfile, 1);
  unlink($containerdigestfile);
  unlink($_) for @tempfiles;
  die("Error while uploading to registry: $result\n") if $result;

  # return digest and public references
  $repository =~ s/^library\/([^\/]+)$/$1/ if $pullserver eq '';
  return ($containerdigests, map {"$pullserver$repository:$_"} @$tags);
}

sub delete_obsolete_tags_from_registry {
  my ($registry, $repository, $containerdigests) = @_;

  return if $registry->{'nodelete'};
  mkdir_p($uploaddir);
  my $containerdigestfile = "$uploaddir/publisher.$$.containerdigests";
  writestr($containerdigestfile, undef, $containerdigests);
  my $registryserver = $registry->{pushserver} || $registry->{server};
  my @cmd = ("$INC[0]/bs_regpush", '--dest-creds', '-', '-X', '-F', $containerdigestfile, $registryserver, $repository);
  print "Deleting obsolete tags: @cmd\n";
  my $result = BSPublisher::Util::qsystem('echo', "$registry->{user}:$registry->{password}\n", 'stdout', '', @cmd);
  unlink($containerdigestfile);
  die("Error while deleting tags from registry: $result\n") if $result;
}

=head2 add_notary_upload - add notary upload information for a repository

=cut

sub add_notary_upload {
  my ($notary_uploads, $registry, $repository, $digest, $tags) = @_;

  return unless $registry->{'notary'};
  my $gun = $registry->{'notary_gunprefix'} || $registry->{'server'};
  $gun =~ s/^https?:\/\///;
  if ($tags) {
    print "adding notary upload for $gun/$repository: @$tags\n";
  } else {
    print "adding empty notary upload for $gun/$repository\n";
  }
  $notary_uploads->{"$gun/$repository"} ||= {'registry' => $registry, 'digests' => '', 'gun' => "$gun/$repository"};
  $notary_uploads->{"$gun/$repository"}->{'digests'} .= $digest if $digest;
}

=head2 upload_to_notary - do all the collected notary uploads

=cut

sub upload_to_notary {
  my ($projid, $notary_uploads, $signargs, $pubkey) = @_;

  my @signargs;
  push @signargs, '--project', $projid if $BSConfig::sign_project;
  push @signargs, @{$signargs || []};

  my $pubkeyfile = "$uploaddir/publisher.$$.notarypubkey";
  mkdir_p($uploaddir);
  unlink($pubkeyfile);
  writestr($pubkeyfile, undef, $pubkey);
  for my $uploadkey (sort keys %$notary_uploads) {
    my $uploaddata = $notary_uploads->{$uploadkey};
    my $registry = $uploaddata->{'registry'};
    my @pubkeyargs = ('-p', $pubkeyfile);
    @pubkeyargs = @{$registry->{'notary_pubkey_args'}} if $registry->{'notary_pubkey_args'};
    my $containerdigestfile = "$uploaddir/publisher.$$.containerdigests";
    writestr($containerdigestfile, undef, $uploaddata->{'digests'} || '');
    my @cmd = ("$INC[0]/bs_notar", '--dest-creds', '-', @signargs, @pubkeyargs, '-F', $containerdigestfile, $registry->{'notary'}, $uploaddata->{'gun'});
    print "Uploading to notary: @cmd\n";
    my $result = BSPublisher::Util::qsystem('echo', "$registry->{user}:$registry->{password}\n", 'stdout', '', @cmd);
    unlink($containerdigestfile);
    if ($result) {
      unlink($pubkeyfile);
      die("Error while uploading to notary: $result\n");
    }
  }
  unlink($pubkeyfile);
}

=head2 delete_from_notary - delete collected repositories

=cut

sub delete_from_notary {
  my ($projid, $notary_uploads) = @_;

  for my $uploadkey (sort keys %$notary_uploads) {
    my $uploaddata = $notary_uploads->{$uploadkey};
    die("delete_from_notary: digest not empty\n") if $uploaddata->{'digests'};
    my $registry = $uploaddata->{'registry'};
    my @cmd = ("$INC[0]/bs_notar", '--dest-creds', '-', '-D', $registry->{'notary'}, $uploaddata->{'gun'});
    print "Deleting from notary: @cmd\n";
    my $result = BSPublisher::Util::qsystem('echo', "$registry->{user}:$registry->{password}\n", 'stdout', '', @cmd);
    die("Error while uploading to notary: $result\n") if $result;
  }
}

=head2 decompress_container - decompress or copy container into a temporary file

 Function returns path to the temporay file

=cut

sub decompress_container {
  my ($in) = @_;

  my %ext2decomp = (
    'tbz' => 'bzcat',
    'tgz' => 'zcat',
    'bz2' => 'bzcat',
    'xz'  => 'xzcat',
    'gz'  => 'zcat',
  );
  my $decomp;
  $decomp = $ext2decomp{$1} if $in =~ /\.([^\.]+)$/;
  $decomp ||= 'cat';
  my ($fh, $tempfile) = tempfile();
  print "Decompressing: '$decomp $in > $tempfile'\n";
  BSPublisher::Util::qsystem('stdout', $tempfile, $decomp, $in);
  return $tempfile;
}

=head2 delete_container_repositories - delete obsolete repositories from the registry/notary

=cut

sub delete_container_repositories {
  my ($extrep, $projid, $repoid, $old_container_repositories) = @_;
  return unless $old_container_repositories;
  upload_all_containers($extrep, $projid, $repoid, undef, undef, undef, 0, $old_container_repositories);
}

sub do_local_uploads {
  my ($extrep, $projid, $repoid, $repository, $gun, $containers, $pubkey, $signargs, $multicontainer, $uptags) = @_;

  my %todo;
  my @tempfiles;
  for my $tag (sort keys %$uptags) {
    my $archs = $uptags->{$tag};
    for my $arch (sort keys %{$archs || {}}) {
      my $p = $archs->{$arch};
      my $containerinfo = $containers->{$p};
      my $file = $containerinfo->{'publishfile'};
      if (!defined($file)) {
        die("need a blobdir for containerinfo uploads\n") unless $containerinfo->{'blobdir'};
      } elsif ($file =~ /\.tar$/) {
	$containerinfo->{'uploadfile'} = $file;
      } elsif ($file =~ /\.tgz$/ && ($containerinfo->{'type'} || '') eq 'helm') {
	$containerinfo->{'uploadfile'} = $file;
      } else {
        my $tmpfile = decompress_container($file);
	$containerinfo->{'uploadfile'} = $tmpfile;
        push @tempfiles, $tmpfile;
      }
      push @{$todo{$tag}}, $containerinfo;
    }
  }
  eval {
    BSPublisher::Registry::push_containers("$projid/$repoid", $repository, $gun, $multicontainer, \%todo, $pubkey, $signargs);
  };
  unlink($_) for @tempfiles;
  die($@) if $@;
}

1;
