#!/usr/bin/perl

use strict;
use warnings;

use lib qw(..);

use Test::More;
use Test::MockModule;

use PVE::Tools qw(file_get_contents file_set_contents run_command);
use PVE::QemuConfig;
use PVE::QemuServer;

my $base_env = {
    storage_config => {
	ids => {
	    local => {
		content => {
		    images => 1,
		},
		path => '/var/lib/vz',
		type => 'dir',
		shared => 0,
	    },
	    'cifs-store' => {
		shared => 1,
		path => '/mnt/pve/cifs-store',
		username => 'guest',
		server => '127.0.0.42',
		type => 'cifs',
		share => 'CIFShare',
		content => {
		    images => 1
		},
	    },
	    'rbd-store' => {
		monhost => '127.0.0.42,127.0.0.21,::1',
		content => {
		    images => 1
		},
		type => 'rbd',
		pool => 'cpool',
		username => 'admin',
		shared => 1
	    },
	    'local-lvm' => {
		vgname => 'pve',
		bwlimit => 'restore=1024',
		type => 'lvmthin',
		thinpool => 'data',
		content => {
		    images => 1,
		}
	    }
	}
    },
    vmid => 8006,
    real_qemu_version => PVE::QemuServer::kvm_user_version(), # not yet mocked
};

my $pci_devs = [
    "0000:00:43.1",
    "0000:00:f4.0",
    "0000:00:ff.1",
    "0000:0f:f2.0",
    "0000:d0:13.0",
    "0000:d0:15.1",
    "0000:d0:17.0",
    "0000:f0:42.0",
    "0000:f0:43.0",
    "0000:f0:43.1",
    "1234:f0:43.1",
];

my $current_test; # = {
#   description => 'Test description', # if available
#   qemu_version => '2.12',
#   host_arch => 'HOST_ARCH',
#   config => { config hash },
#   expected => [ expected outcome cmd line array ],
# };

# use the config description to allow changing environment, fields are:
#   TEST: A single line describing the test, gets outputted
#   QEMU_VERSION: \d+\.\d+(\.\d+)? (defaults to current version)
#   HOST_ARCH: x86_64 | aarch64 (default to x86_64, to make tests stable)
# all fields are optional
sub parse_test($) {
    my ($config_fn) = @_;

    $current_test = {}; # reset

    my $fake_config_fn ="$config_fn/qemu-server/8006.conf";
    my $config_raw = file_get_contents($config_fn);
    my $config = PVE::QemuServer::parse_vm_config($fake_config_fn, $config_raw);

    $current_test->{config} = $config;

    my $description = $config->{description} // '';

    while ($description =~ /^\h*(.*?)\h*$/gm) {
	my $line = $1;
	next if !$line || $line =~ /^#/;
	$line =~ s/^\s+//;
	$line =~ s/\s+$//;

	if ($line =~ /^TEST:\s*(.*)\s*$/) {
	    $current_test->{description} = "$1";
	} elsif ($line =~ /^QEMU_VERSION:\s*(.*)\s*$/) {
	    $current_test->{qemu_version} = "$1";
	} elsif ($line =~ /^HOST_ARCH:\s*(.*)\s*$/) {
	    $current_test->{host_arch} = "$1";
	}
    }
}

my $qemu_server_module;
$qemu_server_module = Test::MockModule->new('PVE::QemuServer');
$qemu_server_module->mock(
    kvm_user_version => sub {
	return $current_test->{qemu_version} // $base_env->{real_qemu_version} // '2.12';
    },
    kvm_version => sub {
	return $current_test->{qemu_version} // $base_env->{real_qemu_version} // '2.12';
    },
    kernel_has_vhost_net => sub {
	return 1; # TODO: make this per-test configurable?
    },
    get_host_arch => sub() {
	return $current_test->{host_arch} // 'x86_64';
    },
    get_initiator_name => sub {
	return 'iqn.1993-08.org.debian:01:aabbccddeeff';
    }
);

my $qemu_server_config;
$qemu_server_config = Test::MockModule->new('PVE::QemuConfig');
$qemu_server_config->mock(
    load_config => sub {
	my ($class, $vmid, $node) = @_;

	return $current_test->{config};
    },
);

my $pve_common_tools;
$pve_common_tools = Test::MockModule->new('PVE::Tools');
$pve_common_tools->mock(
    next_vnc_port => sub {
	my ($family, $address) = @_;

	return '5900';
    },
    next_spice_port => sub {
	my ($family, $address) = @_;

	return '61000';
    },
);

my $pve_common_sysfstools;
$pve_common_sysfstools = Test::MockModule->new('PVE::SysFSTools');
$pve_common_sysfstools->mock(
    lspci => sub {
	my ($filter, $verbose) = @_;

	return [
	    map { { id => $_ } }
	    grep {
		!defined($filter)
		|| (!ref($filter) && $_ =~ m/^(0000:)?\Q$filter\E/)
		|| (ref($filter) eq 'CODE' && $filter->({ id => $_ }))
	    } sort @$pci_devs
	];
    },
);

sub diff($$) {
    my ($a, $b) = @_;
    return if $a eq $b;

    my ($ra, $wa) = POSIX::pipe();
    my ($rb, $wb) = POSIX::pipe();
    my $ha = IO::Handle->new_from_fd($wa, 'w');
    my $hb = IO::Handle->new_from_fd($wb, 'w');

    open my $diffproc, '-|', 'diff', '-up', "/proc/self/fd/$ra", "/proc/self/fd/$rb"
	or die "failed to run program 'diff': $!";
    POSIX::close($ra);
    POSIX::close($rb);

    open my $f1, '<', \$a;
    open my $f2, '<', \$b;
    my ($line1, $line2);
    do {
	$ha->print($line1) if defined($line1 = <$f1>);
	$hb->print($line2) if defined($line2 = <$f2>);
    } while (defined($line1 // $line2));
    close $f1;
    close $f2;
    close $ha;
    close $hb;

    local $/ = undef;
    my $diff = <$diffproc>;
    close $diffproc;
    die "files differ:\n$diff";
}

sub do_test($) {
    my ($config_fn) = @_;

    die "no such input test config: $config_fn\n" if ! -f $config_fn;

    parse_test $config_fn;

    $config_fn =~ /([^\/]+)$/;
    my $testname = "$1";
    if (my $desc = $current_test->{description}) {
	$testname = "'$testname' - $desc";
    }

    my ($vmid, $storecfg) = $base_env->@{qw(vmid storage_config)};

    my $cmdline = PVE::QemuServer::vm_commandline($storecfg, $vmid);

    $cmdline =~ s/ -/ \\\n  -/g; # same as qm showcmd --pretty
    $cmdline .= "\n";

    my $cmd_fn = "$config_fn.cmd";

    if (-f $cmd_fn) {
	my $cmdline_expected = file_get_contents($cmd_fn);

	my $cmd_expected = [ split /\s*\\?\n\s*/, $cmdline_expected ];
	my $cmd = [ split /\s*\\?\n\s*/, $cmdline ];

	# uncomment for easier debugging
	#file_set_contents("$cmd_fn.tmp", $cmdline);

	my $exp = join("\n", @$cmd_expected);
	my $got = join("\n", @$cmd);
	eval { diff($exp, $got) };
	if (my $err = $@) {
	    fail("$testname");
	    note($err);
	} else {
	    pass("$testname");
	}
    } else {
	file_set_contents($cmd_fn, $cmdline);
    }
}

print "testing config to command stabillity\n";

# exec tests
if (my $file = shift) {
    do_test $file;
} else {
    foreach my $file (<cfg2cmd/*.conf>) {
	do_test $file;
    }
}

done_testing();
