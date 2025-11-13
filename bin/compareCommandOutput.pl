#!/usr/bin/perl

# Requires: apt install libnotify-bin

use strict;
use warnings;
use IPC::Run qw(run);
use Data::Dumper;
use Fcntl qw(:flock);

my $command = shift or die "ERROR: No command specified";
print "INFO: command: $command\n";
my $mode = shift || 'compare';
my $urgency = shift || 'normal';
my $time = shift || 10000;

my @parts = split /\//, $command;
my $refFileName = pop @parts;
$refFileName =~ s/\W/_/g;

my $lockfile = "/run/compareCommandOutput.pl.$refFileName.lock";
open my $file, ">", $lockfile or die $!;
flock $file, LOCK_EX|LOCK_NB or die "ERROR: Unable to lock file $!";

my $refOutputDir = "/var/local/localmon";
print "INFO: refOutputDir: $refOutputDir\n";

main(
     $command,
     $refFileName,
     $mode,
     $refOutputDir,
     $urgency,
     $time
    );

sub main
{
    my $command = shift;
    my $refFileName = shift;
    my $mode = shift;
    my $refOutputDir = shift;
    my $urgency = shift;
    my $time = shift;

    my $refFilePath = "$refOutputDir/$refFileName";
    print "INFO: refFilePath: $refFilePath\n";

    if (-e $refFilePath)
    {
        my ($result, $ret) = compareCommandOutput(
                                                  $command,
                                                  $refFilePath
                                                 );

        print "INFO: result:\n$result\n";

        if ($ret)
        {
            notify(
                   "localmon",
                   "Change in <$command>",
                   $result,
                   $urgency,
                   $time
                  );

        }
    }

    if ($mode eq 'save')
    {
        saveCommandOutput(
                          $command,
                          $refFilePath
                         );
    }
    else
    {
        die "ERROR: Reference file '$refFilePath' does not exist" unless -e $refFilePath;
    }
}

sub saveCommandOutput
{
    my $command = shift;
    my $refFilePath = shift;

    my @cmd = split /\s+/, $command;
    print "EXEC: @cmd";

    my $stdout;
    run \@cmd, \undef, \$stdout or die $?;
    print "INFO: stdout:\n$stdout\n";

    open OUT, ">$refFilePath";
    print OUT $stdout;
    close OUT;

    print "INFO: Command output of '$command' successfully saved to '$refFilePath'\n"
}

sub notify
{
    my $appName = shift;
    my $summary = shift;
    my $body = shift;
    my $urgency = shift;
    my $time = shift;

    my @cmd = (
               "sudo",
               "-u kai",
               "DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus",
               "notify-send",
               "-a '$appName'",
               "-u $urgency",
               "-t $time",
               "'$summary'",
               "\'$body\'"
              );

    my $cmd = join ' ', @cmd;

    print "EXEC: $cmd\n";
    system $cmd;
}

sub compareCommandOutput
{
    my $command = shift;
    my $refFilePath = shift;


    my @cmd1 = split /\s+/, $command;
    my @cmd2 = split /\s+/, "diff -u0 $refFilePath -";
    print "EXEC: @cmd1 | @cmd2\n";

    print Dumper \@cmd1, \@cmd2;

    my $stdout;
    run \@cmd1, '|', \@cmd2, \$stdout;
    my $ret = $?;
    print "INFO: ret: $ret\n";

    my $result = removeUninterestingLines($stdout);

    return $result, $ret;
}

sub removeUninterestingLines
{
    my $input = shift;

    my @result;
    foreach my $line (split /\n/, $input)
    {
        next unless $line =~ /^(\+|\-)/;
        next if $line =~ /^(\+\+\+|\-\-\-)/;
        $line =~ s/-|\'/\\-/g;
        #print "LINE: $line\n";
        push @result, $line;
    }

    my $result = join "\n", @result;

    return $result;
}
