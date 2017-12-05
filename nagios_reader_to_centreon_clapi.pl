#!/usr/bin/perl
#
# Copyright 2016 Centreon (http://www.centreon.com/)
#
# Centreon is a full-fledged industry-strength solution that meets
# the needs in IT infrastructure and application monitoring for
# service performance.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# For more information : contact@centreon.com
#

use strict;
use warnings;
use Getopt::Long;
use Nagios::Object::Config;

my $PROGNAME = $0;
my $VERSION = "3.0.0";

my %OPTION = ("help"    => undef,
              "version" => '3',
              "poller"  => "Central",
              "prefix"  => "",
              "config"  => "/usr/local/nagios/etc/",
              "switch"  => undef,
              "filter"  => '^(?!(\.|connector\.cfg))(.*\.cfg)$',
              "default_htpl"  => "",
              "default_stpl"  => "");

Getopt::Long::Configure('bundling');
GetOptions(
    "h|help"                => \$OPTION{'help'},
    "V|version=s"           => \$OPTION{'version'},
    "P|poller=s"            => \$OPTION{'poller'},
    "p|prefix=s"            => \$OPTION{'prefix'},
    "C|config=s"            => \$OPTION{'config'},
    "s|switch"              => \$OPTION{'switch'},
    "f|filter=s"            => \$OPTION{'filter'},
    "default-htpl=s"        => \$OPTION{'default_htpl'},
    "default-stpl=s"        => \$OPTION{'default_stpl'});

my $objects;
my %clapi;
my %contactgroups;
my %hostgroups;
my %servicegroups;
my %host_exported;
my %service_exported;
my %resource_macros;

sub print_usage () {
    print "Version: ";
    print $VERSION."\n";
    print "Usage: ";
    print $PROGNAME."\n";
    print "    -C (--config)      Path to nagios configuration files (must be a directory) (Default: /usr/local/nagios/etc/)\n";
    print "    -V (--version)     Nagios version of the configuration files (Default: 3)\n";
    print "    -P (--poller)      Name of the targeted poller (Default: Central)\n";
    print "    -p (--prefix)      Add a prefix before commands, contacts, templates, groups, etc.\n";
    print "    -s (--switch)      Switch alias and name of contacts for the configurations that need it\n";
    print "    -f (--filter)      Filter files to process with regexp (Default: '^(?!(\\.|connector\\.cfg))(.*\\.cfg)\$\'\)\n";
    print "    --default-htpl     Define default host template for template-less hosts or host templates\n";
    print "    --default-stpl     Define default service template for template-less services or service templates\n";
    print "    -h (--help)        Usage help\n";
}

sub print_help () {
    print "######################################################\n";
    print "#    Copyright (c) 2005-2017 Centreon                #\n";
    print "#    Bugs to http://github.com/nagiosToCentreon      #\n";
    print "######################################################\n";
    print "\n";
    print_usage();
    print "\n";
}

if ($OPTION{'help'}) {
    print_help();
    exit 0;
}

if (! -e $OPTION{'config'}) {
    printf ("Directory %s doesn't exist. Please specify path with '--config' option\n", $OPTION{'config'});
    exit 1;
}

# Export Nagios resource macros
sub export_resources {
    if (-e $OPTION{'config'}."/resource.cfg") {
        open(my $fh, '<', $OPTION{'config'}."/resource.cfg") or die "Can't open $OPTION{'config'}/resource.cfg: $!";
        while (my $line = <$fh>) {
            chomp $line;
            my ($macro, $value) = split('=', $line, 2) if ($line =~ /=/);
            $macro =~ s/\$//g if defined($macro);
            $resource_macros{$macro} = $value if (defined($macro) && defined($value));
        }
        close $fh;

        foreach my $macro (keys %resource_macros) {
            push @{$clapi{RESOURCECFG}}, "RESOURCECFG;ADD;\$".$OPTION{'prefix'}.$macro."\$;".$resource_macros{$macro}.";".$OPTION{'poller'}.";Resource \$".$macro."\$";
        }
    }
}

# Export Nagios commands using Centreon CLAPI format
sub export_commands {
    my @commands_array = @_;

    foreach my $command (@commands_array) {
        next if (!defined($command->{'command_name'}) || $command->{'command_name'} =~ m/bam|check_meta|meta_notify/ || !defined($command->{'command_line'}));
        
        my $command_type = "check";
        if ($command->{'command_name'} =~ m/notify/) {
            $command_type = "notif";
        } elsif ($command->{'command_name'} =~ m/^process\-service\-perfdata|^submit\-host\-check\-result|^submit\-service\-check\-result/) {
            $command_type = "misc";
        }

        if ($OPTION{'prefix'} ne "") {
            foreach my $macro (keys %resource_macros) {
                $command->{'command_line'} =~  s/\$$macro\$/\$$OPTION{'prefix'}$macro\$/g;
            }
        }

        if (defined($command->{'command_line'})) { push @{$clapi{CMD}}, "CMD;ADD;".$OPTION{'prefix'}.$command->{'command_name'}.";".$command_type.";".$command->{'command_line'} };
        if (defined($command->{'comment'})) { push @{$clapi{CMD}}, "CMD;setparam;".$OPTION{'prefix'}.$command->{'command_name'}.";comment;".$command->{'comment'} };
    }
}

# Export Nagios timepriods using Centreon CLAPI format
sub export_timeperiods {
    my @timeperiods_array = @_;

    foreach my $timeperiod (@timeperiods_array) {
        next if (!defined($timeperiod->{'timeperiod_name'}) || $timeperiod->{'timeperiod_name'} =~ m/centreon\-bam|meta\_timeperiod/);

        if (defined($timeperiod->{'alias'})) { push @{$clapi{TP}}, "TP;ADD;".$OPTION{'prefix'}.$timeperiod->{'timeperiod_name'}.";".$timeperiod->{'alias'} };
        if (defined($timeperiod->{'sunday'})) { push @{$clapi{TP}}, "TP;setparam;".$OPTION{'prefix'}.$timeperiod->{'timeperiod_name'}.";tp_sunday;".$timeperiod->{'sunday'} };
        if (defined($timeperiod->{'monday'})) { push @{$clapi{TP}}, "TP;setparam;".$OPTION{'prefix'}.$timeperiod->{'timeperiod_name'}.";tp_monday;".$timeperiod->{'monday'} };
        if (defined($timeperiod->{'tuesday'})) { push @{$clapi{TP}}, "TP;setparam;".$OPTION{'prefix'}.$timeperiod->{'timeperiod_name'}.";tp_tuesday;".$timeperiod->{'tuesday'} };
        if (defined($timeperiod->{'wednesday'})) { push @{$clapi{TP}}, "TP;setparam;".$OPTION{'prefix'}.$timeperiod->{'timeperiod_name'}.";tp_wednesday;".$timeperiod->{'wednesday'} };
        if (defined($timeperiod->{'thursday'})) { push @{$clapi{TP}}, "TP;setparam;".$OPTION{'prefix'}.$timeperiod->{'timeperiod_name'}.";tp_thursday;".$timeperiod->{'thursday'} };
        if (defined($timeperiod->{'friday'})) { push @{$clapi{TP}}, "TP;setparam;".$OPTION{'prefix'}.$timeperiod->{'timeperiod_name'}.";tp_friday;".$timeperiod->{'friday'} };
        if (defined($timeperiod->{'saturday'})) { push @{$clapi{TP}}, "TP;setparam;".$OPTION{'prefix'}.$timeperiod->{'timeperiod_name'}.";tp_saturday;".$timeperiod->{'saturday'} };
    }
}

# Export Nagios contacts using Centreon CLAPI format
sub export_contacts {
    my @contacts_array = @_;

    foreach my $contact (@contacts_array) {
        next if (!defined($contact->{'alias'}) || !defined($contact->{'contact_name'}) || $contact->{'contact_name'} =~ m/centreon\-bam|\_Module\_BAM/);

        $contact->{'alias'} =~ s/ /_/g;
        $contact->{'contact_name'} =~ s/ /_/g;
        if (defined($contact->{'contact_name'})) { push @{$clapi{CONTACT}}, "CONTACT;ADD;".$contact->{'alias'}.";".$OPTION{'prefix'}.$contact->{'contact_name'}.";".((defined($contact->{'email'})) ? $contact->{'email'} : "").";".((defined($contact->{'pager'})) ? $contact->{'pager'} : "").";0;0;en_US;local" };
        if (defined($contact->{'host_notification_period'})) { push @{$clapi{CONTACT}}, "CONTACT;setparam;".$OPTION{'prefix'}.$contact->{'contact_name'}.";hostnotifperiod;". ((ref $contact->{'host_notification_period'} eq "Nagios::TimePeriod") ? $OPTION{'prefix'}.${$contact->{'host_notification_period'}}{'timeperiod_name'} : $OPTION{'prefix'}.$contact->{'host_notification_period'}) };
        if (defined($contact->{'service_notification_period'})) { push @{$clapi{CONTACT}}, "CONTACT;setparam;".$OPTION{'prefix'}.$contact->{'contact_name'}.";svcnotifperiod;". ((ref $contact->{'service_notification_period'} eq "Nagios::TimePeriod") ? $OPTION{'prefix'}.${$contact->{'service_notification_period'}}{'timeperiod_name'} : $OPTION{'prefix'}.$contact->{'service_notification_period'}) };
        if (defined($contact->{'host_notification_options'})) { push @{$clapi{CONTACT}}, "CONTACT;setparam;".$OPTION{'prefix'}.$contact->{'contact_name'}.";hostnotifopt;".((ref $contact->{'host_notification_options'} eq "ARRAY") ? join(",", @{$contact->{'host_notification_options'}}) : $contact->{'host_notification_options'}) };
		if (defined($contact->{'service_notification_options'})) { push @{$clapi{CONTACT}}, "CONTACT;setparam;".$OPTION{'prefix'}.$contact->{'contact_name'}.";servicenotifopt;".((ref $contact->{'service_notification_options'} eq "ARRAY") ? join(",", @{$contact->{'service_notification_options'}}) : $contact->{'service_notification_options'}) };
        if (defined($contact->{'host_notifications_enabled'})) { push @{$clapi{CONTACT}}, "CONTACT;setparam;".$OPTION{'prefix'}.$contact->{'contact_name'}.";contact_enable_notifications;".$contact->{'host_notifications_enabled'} };
        if (defined($contact->{'host_notification_commands'})) { push @{$clapi{CONTACT}}, "CONTACT;setparam;".$OPTION{'prefix'}.$contact->{'contact_name'}.";hostnotifcmd;".((ref $contact->{'host_notification_commands'} eq "ARRAY") ? join("|", (my @hostnotifcmd = map { $OPTION{'prefix'}.$_ } @{$contact->{'host_notification_commands'}})) : $OPTION{'prefix'}.$contact->{'host_notification_commands'}) };
        if (defined($contact->{'service_notification_commands'})) { push @{$clapi{CONTACT}}, "CONTACT;setparam;".$OPTION{'prefix'}.$contact->{'contact_name'}.";svcnotifcmd;".((ref $contact->{'service_notification_commands'} eq "ARRAY") ? join("|", (my @hostnotifcmd = map { $OPTION{'prefix'}.$_ } @{$contact->{'service_notification_commands'}})) : $OPTION{'prefix'}.$contact->{'service_notification_commands'}) };
        if (defined($contact->{'address1'})) { push @{$clapi{CONTACT}}, "CONTACT;setparam;".$OPTION{'prefix'}.$contact->{'contact_name'}.";address1;".$contact->{'address1'} };
        if (defined($contact->{'address2'})) { push @{$clapi{CONTACT}}, "CONTACT;setparam;".$OPTION{'prefix'}.$contact->{'contact_name'}.";address2;".$contact->{'address2'} };
        if (defined($contact->{'address3'})) { push @{$clapi{CONTACT}}, "CONTACT;setparam;".$OPTION{'prefix'}.$contact->{'contact_name'}.";address3;".$contact->{'address3'} };
        if (defined($contact->{'address4'})) { push @{$clapi{CONTACT}}, "CONTACT;setparam;".$OPTION{'prefix'}.$contact->{'contact_name'}.";address4;".$contact->{'address4'} };
        if (defined($contact->{'address5'})) { push @{$clapi{CONTACT}}, "CONTACT;setparam;".$OPTION{'prefix'}.$contact->{'contact_name'}.";address5;".$contact->{'address5'} };
        if (defined($contact->{'address6'})) { push @{$clapi{CONTACT}}, "CONTACT;setparam;".$OPTION{'prefix'}.$contact->{'contact_name'}.";address6;".$contact->{'address6'} };
        if (defined($contact->{'register'})) { push @{$clapi{CONTACT}}, "CONTACT;setparam;".$OPTION{'prefix'}.$contact->{'contact_name'}.";register;".$contact->{'register'} };
        if (defined($contact->{'comment'})) { push @{$clapi{CONTACT}}, "CONTACT;setparam;".$OPTION{'prefix'}.$contact->{'contact_name'}.";comment;".$contact->{'comment'} };
        if (defined($contact->{'contact_name'})) { push @{$clapi{CONTACT}}, "CONTACT;setparam;".$OPTION{'prefix'}.$contact->{'contact_name'}.";contact_activate;1" };
        if (defined($contact->{'timezone'})) {
            $contact->{'timezone'} =~ s/://g;
            push @{$clapi{CONTACT}}, "CONTACT;setparam;".$OPTION{'prefix'}.$contact->{'contact_name'}.";timezone;".$contact->{'timezone'};
        }
        
        # Add contact to contactgroups
        if (defined($contact->{'contactgroups'})) {
            if (ref $contact->{'contactgroups'}) {
                foreach my $contactgroup (@{$contact->{'contactgroups'}}) {
                    push @{$contactgroups{$contactgroup}}, $contact->{'contact_name'};
                }
            } else {
                push @{$contactgroups{$contact->{'contactgroups'}}}, $contact->{'contact_name'};
            }
        }

        if (!defined($OPTION{'switch'})) {
            push @{$clapi{CONTACT_SWITCH}}, "CONTACT;setparam;".$OPTION{'prefix'}.$contact->{'contact_name'}.";name;".$contact->{'contact_name'};
            push @{$clapi{CONTACT_SWITCH}}, "CONTACT;setparam;".$OPTION{'prefix'}.$contact->{'contact_name'}.";alias;".$OPTION{'prefix'}.$contact->{'alias'};
        }
    }
}

# Export Nagios contactgroups using Centreon CLAPI format
sub export_contactgroups {
    my @contactgroups_array = @_;

    foreach my $contactgroup (@contactgroups_array) {
        next if (!defined($contactgroup->{'contactgroup_name'}) || $contactgroup->{'contactgroup_name'} =~ m/centreon\-bam\-contactgroup|\_Module\_BAM/);

        my %contacts_exported;

        push @{$clapi{CG}}, "CG;ADD;".$OPTION{'prefix'}.$contactgroup->{'contactgroup_name'}.";".$contactgroup->{'alias'};
        push @{$clapi{CG}}, "CG;setparam;".$OPTION{'prefix'}.$contactgroup->{'contactgroup_name'}.";cg_activate;1";
        push @{$clapi{CG}}, "CG;setparam;".$OPTION{'prefix'}.$contactgroup->{'contactgroup_name'}.";cg_type;local";

        # Loop to add contacts from contactgroup definition
        if (defined($contactgroup->{'members'})) {
            if (ref $contactgroup->{'members'}) {
                foreach my $contact (@{$contactgroup->{'members'}}) {
                    if (!defined($contacts_exported{$contact})) {
                        push @{$clapi{CG}}, "CG;addcontact;".$OPTION{'prefix'}.$contactgroup->{'contactgroup_name'}.";".$OPTION{'prefix'}.$contact;
                        $contacts_exported{$contact} = 1;
                    }
                }
            } else {
                push @{$clapi{CG}}, "CG;addcontact;".$OPTION{'prefix'}.$contactgroup->{'contactgroup_name'}.";".$OPTION{'prefix'}.$contactgroup->{'members'};
                $contacts_exported{$contactgroup->{'members'}} = 1;
            }
        }
        
        # Loop to add contacts from contact definition
        if (defined($contactgroups{$contactgroup->{'contactgroup_name'}} )) {
            foreach my $contact (@{$contactgroups{$contactgroup->{'contactgroup_name'}}}) {
                if (!defined ($contacts_exported{$contact})) {
                    push @{$clapi{CG}}, "CG;addcontact;".$OPTION{'prefix'}.$contactgroup->{'contactgroup_name'}.";".$OPTION{'prefix'}.$contact;
                }
            }
        }
    }
}

# Export Nagios hosts and templates of hosts using Centreon CLAPI format
sub export_hosts {
    my @hosts_array = @_ ;
    my @templates;

    foreach my $host (@hosts_array) {
        next if (ref $host ne "Nagios::Host");
        if (!defined($host->{'host_name'})) { $host->{'host_name'} = $host->{'name'} };

        # If the host uses templates, we export the templates first
        if (defined($host->{'use'})) {
            @templates = split(',', $host->{'use'});

            foreach my $template (@templates) {
                if (!defined($host_exported{$template})) { export_hosts($objects->find_object($template, "Nagios::Host")) };
            }
        }

        if (defined($host->{'host_name'}) && ($host->{'host_name'} !~ m/\_Module\_BAM|\_Module\_Meta/) && !defined($host_exported{$host->{'host_name'}})) {
            my $type = "HOST";
            my $prefix = $OPTION{'prefix'};
            
            if (!defined($host->register) || $host->register == 0 || !defined($host->{'address'})) {
                $type = "HTPL";
                push @{$clapi{$type}}, "HTPL;ADD;".$prefix.$host->{'host_name'}.";".(defined($host->{'alias'}) ? $host->{'alias'} : $host->{'host_name'}).";;".((@templates) ? join("|", (my @template = map { $OPTION{'prefix'}.$_ } @templates)) : $OPTION{'default_htpl'}).";;";
                
            } else {
                push @{$clapi{$type}}, "HOST;ADD;".$host->{'host_name'}.";".(defined($host->{'alias'}) ? $host->{'alias'} : $host->{'host_name'}).";".$host->{'address'}.";".((@templates) ? join("|", (my @template = map { $OPTION{'prefix'}.$_ } @templates)) : $OPTION{'default_htpl'}).";".$OPTION{'poller'}.";";
                $prefix = "";
            }
            if (defined($host->{'2d_coords'})) { push @{$clapi{$type}}, $type.";setparam;".$prefix.$host->{'host_name'}.";2d_coords;".$host->{'2d_coords'} };
            if (defined($host->{'3d_coords'})) { push @{$clapi{$type}}, $type.";setparam;".$prefix.$host->{'host_name'}.";3d_coords;".$host->{'3d_coords'} };
            if (defined($host->{'action_url'})) { push @{$clapi{$type}}, $type.";setparam;".$prefix.$host->{'host_name'}.";action_url;".$host->{'action_url'} };
            if (defined($host->{'active_checks_enabled'})) { push @{$clapi{$type}}, $type.";setparam;".$prefix.$host->{'host_name'}.";active_checks_enabled;".$host->{'active_checks_enabled'} };
            if (defined($host->{'check_command'})) {
                my ($check_command, $check_command_arguments) = split('!', $host->{'check_command'}, 2);
                if (defined($check_command) && $check_command ne "") { push @{$clapi{$type}}, $type.";setparam;".$prefix.$host->{'host_name'}.";check_command;".$OPTION{'prefix'}.$check_command };
                if (defined($check_command_arguments) && $check_command_arguments ne "") {
                    if ($OPTION{'prefix'} ne "") {
                        foreach my $macro (keys %resource_macros) {
                            $check_command_arguments =~  s/\$$macro\$/\$$OPTION{'prefix'}$macro\$/g;
                        }
                    }
                    push @{$clapi{$type}}, $type.";setparam;".$prefix.$host->{'host_name'}.";check_command_arguments;!".$check_command_arguments
                }
            }
            if (defined($host->{'check_interval'})) { push @{$clapi{$type}}, $type.";setparam;".$prefix.$host->{'host_name'}.";check_interval;".$host->{'check_interval'} };
            if (defined($host->{'normal_check_interval'})) { push @{$clapi{$type}}, $type.";setparam;".$prefix.$host->{'host_name'}.";check_interval;".$host->{'normal_check_interval'} };
            if (defined($host->{'check_freshness'})) { push @{$clapi{$type}}, $type.";setparam;".$prefix.$host->{'host_name'}.";check_freshness;".$host->{'check_freshness'} };
            if (defined($host->{'freshness_threshold'})) { push @{$clapi{$type}}, $type.";setparam;".$prefix.$host->{'host_name'}.";freshness_threshold;".$host->{'freshness_threshold'} };
            if (defined($host->{'check_period'})) { push @{$clapi{$type}}, $type.";setparam;".$prefix.$host->{'host_name'}.";check_period;".((ref $host->{'check_period'} eq "Nagios::TimePeriod") ? $OPTION{'prefix'}.${$host->{'check_period'}}{'timeperiod_name'} : $OPTION{'prefix'}.$host->{'check_period'}) };
            if (defined($host->{'event_handler'})) { push @{$clapi{$type}}, $type.";setparam;".$prefix.$host->{'host_name'}.";event_handler;".$host->{'event_handler'} };
            if (defined($host->{'event_handler_enabled'})) { push @{$clapi{$type}}, $type.";setparam;".$prefix.$host->{'host_name'}.";event_handler_enabled;".$host->{'event_handler_enabled'} };
            if (defined($host->{'first_notification_delay'})) { push @{$clapi{$type}}, $type.";setparam;".$prefix.$host->{'host_name'}.";first_notification_delay;".$host->{'first_notification_delay'} };
            if (defined($host->{'flap_detection_enabled'})) { push @{$clapi{$type}}, $type.";setparam;".$prefix.$host->{'host_name'}.";flap_detection_enabled;".$host->{'flap_detection_enabled'} };
            if (defined($host->{'low_flap_threshold'})) { push @{$clapi{$type}}, $type.";setparam;".$prefix.$host->{'host_name'}.";low_flap_threshold;".$host->{'low_flap_threshold'} };
            if (defined($host->{'high_flap_threshold'})) { push @{$clapi{$type}}, $type.";setparam;".$prefix.$host->{'host_name'}.";high_flap_threshold;".$host->{'high_flap_threshold'} };
            if (defined($host->{'max_check_attempts'})) { push @{$clapi{$type}}, $type.";setparam;".$prefix.$host->{'host_name'}.";max_check_attempts;".$host->{'max_check_attempts'} };
            if (defined($host->{'notes'})) { push @{$clapi{$type}}, $type.";setparam;".$prefix.$host->{'host_name'}.";notes;".$host->{'notes'} };
            if (defined($host->{'notes_url'})) { push @{$clapi{$type}}, $type.";setparam;".$prefix.$host->{'host_name'}.";notes_url;".$host->{'notes_url'} };
            if (defined($host->{'action_url'})) { push @{$clapi{$type}}, $type.";setparam;".$prefix.$host->{'host_name'}.";action_url;".$host->{'action_url'} };
            if (defined($host->{'notifications_enabled'})) { push @{$clapi{$type}}, $type.";setparam;".$prefix.$host->{'host_name'}.";notifications_enabled;".$host->{'notifications_enabled'} };
            if (defined($host->{'notification_interval'})) { push @{$clapi{$type}}, $type.";setparam;".$prefix.$host->{'host_name'}.";notification_interval;".$host->{'notification_interval'} };
		    if (defined($host->{'notification_options'})) { push @{$clapi{$type}}, $type.";setparam;".$prefix.$host->{'host_name'}.";notification_options;".((ref $host->{'notification_options'} eq "ARRAY") ? join(",", @{$host->{'notification_options'}}) : $host->{'notification_options'}) };
            if (defined($host->{'notification_period'})) {push @{$clapi{$type}}, $type.";setparam;".$prefix.$host->{'host_name'}.";notification_period;".((ref $host->{'notification_period'} eq "Nagios::TimePeriod") ? $OPTION{'prefix'}.${$host->{'notification_period'}}{'timeperiod_name'} : $OPTION{'prefix'}.$host->{'notification_period'}) };
            if (defined($host->{'obsess_over_host'})) { push @{$clapi{$type}}, $type.";setparam;".$prefix.$host->{'host_name'}.";obsess_over_host;".$host->{'obsess_over_host'} };
            if (defined($host->{'passive_checks_enabled'})) { push @{$clapi{$type}}, $type.";setparam;".$prefix.$host->{'host_name'}.";passive_checks_enabled;".$host->{'passive_checks_enabled'} };
            if (defined($host->{'process_perf_data'})) { push @{$clapi{$type}}, $type.";setparam;".$prefix.$host->{'host_name'}.";process_perf_data;".$host->{'process_perf_data'} };
            if (defined($host->{'retain_nonstatus_information'})) { push @{$clapi{$type}}, $type.";setparam;".$prefix.$host->{'host_name'}.";retain_nonstatus_information;".$host->{'retain_nonstatus_information'} };
            if (defined($host->{'retain_status_information'})) { push @{$clapi{$type}}, $type.";setparam;".$prefix.$host->{'host_name'}.";retain_status_information;".$host->{'retain_status_information'} };
            if (defined($host->{'retry_interval'})) { push @{$clapi{$type}}, $type.";setparam;".$prefix.$host->{'host_name'}.";retry_check_interval;".$host->{'retry_interval'} };
            if (defined($host->{'stalking_options'})) { push @{$clapi{$type}}, $type.";setparam;".$prefix.$host->{'host_name'}.";stalking_options;".((ref $host->{'stalking_options'} eq "ARRAY") ? join(",", @{$host->{'stalking_options'}}) : $host->{'stalking_options'}) };
            if (defined($host->{'event_handler'})) {
                my ($handler_command, $handler_command_arguments) = split('!', $host->{'event_handler'}, 2);
                if (defined($handler_command) && $handler_command ne "") { push @{$clapi{$type}}, $type.";setparam;".$prefix.$host->{'host_name'}.";event_handler;".$OPTION{'prefix'}.$handler_command };
                if (defined($handler_command_arguments) && $handler_command_arguments ne "") {
                    if ($OPTION{'prefix'} ne "") {
                        foreach my $macro (keys %resource_macros) {
                            $handler_command_arguments =~  s/\$$macro\$/\$$OPTION{'prefix'}$macro\$/g;
                        }
                    }
                    push @{$clapi{$type}}, $type.";setparam;".$prefix.$host->{'host_name'}.";event_handler_arguments;!".$handler_command_arguments
                }
            }
            if (defined($host->{'icon_image'})) { push @{$clapi{$type}}, $type.";setparam;".$prefix.$host->{'host_name'}.";icon_image;".$host->{'icon_image'} };
            if (defined($host->{'icon_image_alt'})) { push @{$clapi{$type}}, $type.";setparam;".$prefix.$host->{'host_name'}.";icon_image_alt;".$host->{'icon_image_alt'} };
            if (defined($host->{'statusmap_image'})) { push @{$clapi{$type}}, $type.";setparam;".$prefix.$host->{'host_name'}.";statusmap_image;".$host->{'statusmap_image'} };
            if (defined($host->{'vrml_image'})) { push @{$clapi{$type}}, $type.";setparam;".$prefix.$host->{'host_name'}.";vrml_image;".$host->{'vrml_image'} };
            if (defined($host->{'recovery_notification_delay'})) { push @{$clapi{$type}}, $type.";setparam;".$prefix.$host->{'host_name'}.";recovery_notification_delay;".$host->{'recovery_notification_delay'} };
            if (defined($host->{'_SNMPVERSION'})) { push @{$clapi{$type}}, $type.";setparam;".$prefix.$host->{'host_name'}.";snmp_version;".$host->{'_SNMPVERSION'} };
            if (defined($host->{'_SNMPCOMMUNITY'})) { push @{$clapi{$type}}, $type.";setparam;".$prefix.$host->{'host_name'}.";snmp_community;".$host->{'_SNMPCOMMUNITY'} };
            if (defined($host->{'timezone'})) {
                $host->{'timezone'} =~ s/://g;
                push @{$clapi{$type}}, $type.";setparam;".$prefix.$host->{'host_name'}.";timezone;".$host->{'timezone'};
            }

            # Add parents
            if (defined($host->{'parents'})) {
                if (ref defined($host->{'parents'})) {
                    foreach my $parent (@{$host->{'parents'}}) {
                        if (!defined($host_exported{$parent})) { export_hosts($objects->find_object($parent, "Nagios::Host")) };
                    }
                    push @{$clapi{$type}}, $type.";setparent;".$prefix.$host->{'host_name'}.";".(join("|", (my @parents = map { $_->name } @{$host->{'parents'}})))
                } else {
                    if (!defined($host_exported{$host->{'parents'}})) { export_hosts($objects->find_object($host->{'parents'}, "Nagios::Host")) };
                    push @{$clapi{$type}}, $type.";setparent;".$prefix.$host->{'host_name'}.";".$host->{'parents'};
                }
            }
            
            # Macros handling
            foreach my $macro ($host->list_attributes()) {
                if ($macro =~ m/^_/ && $macro !~ m/SNMP|HOST_ID/ && defined($host->{$macro})) {
                    $macro =~ s/_//;
                    push @{$clapi{$type}}, $type.";setmacro;".$prefix.$host->{'host_name'}.";".$macro.";".$host->{"_".$macro}.";0;";
                }
            }

            # Add contactgroups to host
            if (defined($host->{'contact_groups'})) {
                if (ref $host->{'contact_groups'}) { push @{$clapi{$type}}, $type.";setcontactgroup;".$prefix.$host->{'host_name'}.";".(join("|", (my @contactgroups = map { (ref $_ ne "Nagios::ContactGroup") ? $OPTION{'prefix'}.$_ : $OPTION{'prefix'}.$_->{'contactgroup_name'} } @{$host->{'contact_groups'}}))) };
                if (not ref $host->{'contact_groups'}) { push @{$clapi{$type}}, $type.";setcontactgroup;".$prefix.$host->{'host_name'}.";".$OPTION{'prefix'}.$host->{'contact_groups'} };
            }

            # Add contacts to host
            if (defined($host->{'contacts'})) {
                if (ref $host->{'contacts'}) { push @{$clapi{$type}}, $type.";setcontact;".$prefix.$host->{'host_name'}.";".(join("|", (my @contactgroups = map { (ref $_ ne "Nagios::Contact") ? $OPTION{'prefix'}.$_ : $OPTION{'prefix'}.$_->{'contact_name'} } @{$host->{'contacts'}}))) };
                if (not ref $host->{'contacts'}) { push @{$clapi{$type}}, $type.";setcontact;".$prefix.$host->{'host_name'}.";".$OPTION{'prefix'}.$host->{'contacts'} };
            }

            # Add host to hostgroups
            if (defined ($host->{'hostgroups'})) {
                if (ref $host->{'hostgroups'}) {
                    foreach my $hostgroup (@{$host->{'hostgroups'}}) {
                        push @{$hostgroups{$hostgroup}}, $host->{'host_name'};
                    }
                } else {
                    push @{$hostgroups{$host->{'hostgroups'}}}, $host->{'host_name'};
                }
            }

            # To do not export twice template
            $host_exported{$host->{'host_name'}} = 1;
        }
    }
}

# Export Nagios hostgroups using Centreon CLAPI format
sub export_hostgroups {
    my @hostgroups_array = @_ ; 

    foreach my $hostgroup (@hostgroups_array) {
        next if (!defined($hostgroup->{'hostgroup_name'}) || $hostgroup->{'hostgroup_name'} =~ m/centreon\-bam\-contactgroup|\_Module\_BAM/);

        my %hostgroups_exported;

        push @{$clapi{HG}}, "HG;ADD;".$OPTION{'prefix'}.$hostgroup->{'hostgroup_name'}.";".$hostgroup->{'alias'};
        push @{$clapi{HG}}, "HG;setparam;".$OPTION{'prefix'}.$hostgroup->{'hostgroup_name'}.";hg_activate;1";

        # Loop to add hosts from hostgroups definition
        if (defined($hostgroup->{'members'})) {
            if (ref $hostgroup->{'members'}) {
                foreach my $host (@{$hostgroup->{'members'}}) {
                    if (!defined($hostgroups_exported{$host})) {
                        push @{$clapi{HG}}, "HG;addhost;".$OPTION{'prefix'}.$hostgroup->{'hostgroup_name'}.";".$host;
                        $hostgroups_exported{$host} = 1;
                    }
                }
            } elsif ($hostgroup->{'members'} eq "*") {
                foreach my $host (@{$objects->{host_list}}) {
                    if (defined($host->{'host_name'}) && ($host->{'host_name'} !~ m/\_Module\_BAM|\_Module\_Meta/) && defined($host_exported{$host->{'host_name'}})) {
                        if (defined($host->register) && $host->register == 1 && defined($host->{'address'})) {
                            push @{$clapi{HG}}, "HG;addhost;".$OPTION{'prefix'}.$hostgroup->{'hostgroup_name'}.";".$host->{'host_name'};
                            $hostgroups_exported{$host->{'host_name'}} = 1;
                        }
                    }
                }
            } else {
                push @{$clapi{HG}}, "HG;addhost;".$OPTION{'prefix'}.$hostgroup->{'hostgroup_name'}.";".$hostgroup->{'members'};
                $hostgroups_exported{$hostgroup->{'members'}} = 1;
            }
        }

        # Loop to add hosts from host definition
        if (defined($hostgroups{$hostgroup->{'hostgroup_name'}})) {
            foreach my $host (@{$hostgroups{$hostgroup->{'hostgroup_name'}}}) {
                if (!defined($hostgroups_exported{$host})) {
                    push @{$clapi{HG}}, "HG;addhost;".$OPTION{'prefix'}.$hostgroup->{'hostgroup_name'}.";".$host;
                }
            }
        }
    }
}

# Export Nagios services and templates of services using Centreon CLAPI format
sub export_services {
    my @services_array = @_;

    foreach my $service (@services_array) {
        next if (ref $service ne "Nagios::Service");
        if (defined($service->{'name'}) && ($service->{'name'} !~ m/^ba\_|^meta\_/) && !defined($service_exported{$service->{'name'}}) || defined($service->{'hostgroup_name'})) {
            # If the service uses a template, we export the template first
            if (defined($service->{'use'})) {
                export_services($objects->find_object($service->{'use'}, "Nagios::Service"));
            }
            
            # Create template of service for services by hostgroups
            if (defined($service->{'hostgroup_name'})) {
                $service->{'name'} = "Service-By-Hg-".$service->{'service_description'};
            }

            if (defined($service->{'name'})) { push @{$clapi{STPL}}, "STPL;ADD;".$OPTION{'prefix'}.$service->{'name'}.";".$service->{'service_description'}.";".(defined($service->{'use'}) ? $OPTION{'prefix'}.$service->{'use'} : $OPTION{'default_stpl'}) };
            if (defined($service->{'is_volatile'})) { push @{$clapi{STPL}}, "STPL;setparam;".$OPTION{'prefix'}.$service->{'name'}.";is_volatile;".$service->{'is_volatile'} };
            if (defined($service->{'check_period'})) { push @{$clapi{STPL}}, "STPL;setparam;".$OPTION{'prefix'}.$service->{'name'}.";check_period;".((ref $service->{'check_period'} eq "Nagios::TimePeriod") ? $OPTION{'prefix'}.${$service->{'check_period'}}{'timeperiod_name'} : $OPTION{'prefix'}.$service->{'check_period'}) };
            if (defined($service->{'check_command'})) {
                my ($check_command, $check_command_arguments) = split('!', (ref $service->{'check_command'} eq "Nagios::Command") ? ${$service->{'check_command'}}{'command_name'} : $service->{'check_command'}, 2);
                if (defined($check_command) && $check_command ne "") { push @{$clapi{STPL}}, "STPL;setparam;".$OPTION{'prefix'}.$service->{'name'}.";check_command;".$OPTION{'prefix'}.$check_command };
                if (defined($check_command_arguments) && $check_command_arguments ne "") {
                    if ($OPTION{'prefix'} ne "") {
                        foreach my $macro (keys %resource_macros) {
                            $check_command_arguments =~  s/\$$macro\$/\$$OPTION{'prefix'}$macro\$/g;
                        }
                    }
                    push @{$clapi{STPL}}, "STPL;setparam;".$OPTION{'prefix'}.$service->{'name'}.";check_command_arguments;!".$check_command_arguments
                }
            }
            if (defined($service->{'max_check_attempts'})) { push @{$clapi{STPL}}, "STPL;setparam;".$OPTION{'prefix'}.$service->{'name'}.";max_check_attempts;".$service->{'max_check_attempts'} };
            if (defined($service->{'check_interval'})) { push @{$clapi{STPL}}, "STPL;setparam;".$OPTION{'prefix'}.$service->{'name'}.";normal_check_interval;".$service->{'check_interval'} };
            if (defined($service->{'normal_check_interval'})) { push @{$clapi{STPL}}, "STPL;setparam;".$OPTION{'prefix'}.$service->{'name'}.";normal_check_interval;".$service->{'normal_check_interval'} };
            if (defined($service->{'retry_interval'})) { push @{$clapi{STPL}}, "STPL;setparam;".$OPTION{'prefix'}.$service->{'name'}.";retry_check_interval;".$service->{'retry_interval'} };
            if (defined($service->{'active_checks_enabled'})) { push @{$clapi{STPL}}, "STPL;setparam;".$OPTION{'prefix'}.$service->{'name'}.";active_checks_enabled;".$service->{'active_checks_enabled'} };
            if (defined($service->{'passive_checks_enabled'})) { push @{$clapi{STPL}}, "STPL;setparam;".$OPTION{'prefix'}.$service->{'name'}.";passive_checks_enabled;".$service->{'passive_checks_enabled'} };
            if (defined($service->{'notifications_enabled'})) { push @{$clapi{STPL}}, "STPL;setparam;".$OPTION{'prefix'}.$service->{'name'}.";notifications_enabled;".$service->{'notifications_enabled'} };
            if (defined($service->{'notification_interval'})) { push @{$clapi{STPL}}, "STPL;setparam;".$OPTION{'prefix'}.$service->{'name'}.";notification_interval;".$service->{'notification_interval'} };
            if (defined($service->{'notification_period'})) { push @{$clapi{STPL}}, "STPL;setparam;".$OPTION{'prefix'}.$service->{'name'}.";notification_period;".((ref $service->{'notification_period'} eq "Nagios::TimePeriod") ? $OPTION{'prefix'}.${$service->{'notification_period'}}{'timeperiod_name'} : $OPTION{'prefix'}.$service->{'notification_period'}) };
            if (defined($service->{'notification_options'})) { push @{$clapi{STPL}}, "STPL;setparam;".$OPTION{'prefix'}.$service->{'name'}.";notification_options;".((ref $service->{'notification_options'}  eq "ARRAY") ? join(",", @{$service->{'notification_options'}}) : $service->{'notification_options'}) };
            if (defined($service->{'first_notification_delay'})) { push @{$clapi{STPL}}, "STPL;setparam;".$OPTION{'prefix'}.$service->{'name'}.";first_notification_delay;".$service->{'first_notification_delay'} };
            if (defined($service->{'parallelize_check'})) { push @{$clapi{STPL}}, "STPL;setparam;".$OPTION{'prefix'}.$service->{'name'}.";parallelize_check;".$service->{'parallelize_check'} };
            if (defined($service->{'obsess_over_service'})) { push @{$clapi{STPL}}, "STPL;setparam;".$OPTION{'prefix'}.$service->{'name'}.";obsess_over_service;".$service->{'obsess_over_service'} };
            if (defined($service->{'check_freshness'})) { push @{$clapi{STPL}}, "STPL;setparam;".$OPTION{'prefix'}.$service->{'name'}.";check_freshness;".$service->{'check_freshness'} };
            if (defined($service->{'freshness_threshold'})) { push @{$clapi{STPL}}, "STPL;setparam;".$OPTION{'prefix'}.$service->{'name'}.";freshness_threshold;".$service->{'freshness_threshold'} };
            if (defined($service->{'flap_detection_enabled'})) { push @{$clapi{STPL}}, "STPL;setparam;".$OPTION{'prefix'}.$service->{'name'}.";flap_detection_enabled;".$service->{'flap_detection_enabled'} };
            if (defined($service->{'low_flap_threshold'})) { push @{$clapi{STPL}}, "STPL;setparam;".$OPTION{'prefix'}.$service->{'name'}.";low_flap_threshold;".$service->{'low_flap_threshold'} };
            if (defined($service->{'high_flap_threshold'})) { push @{$clapi{STPL}}, "STPL;setparam;".$OPTION{'prefix'}.$service->{'name'}.";high_flap_threshold;".$service->{'high_flap_threshold'} };
            if (defined($service->{'process_perf_data'})) { push @{$clapi{STPL}}, "STPL;setparam;".$OPTION{'prefix'}.$service->{'name'}.";process_perf_data;".$service->{'process_perf_data'} };
            if (defined($service->{'retain_status_information'})) { push @{$clapi{STPL}}, "STPL;setparam;".$OPTION{'prefix'}.$service->{'name'}.";retain_status_information;".$service->{'retain_status_information'} };
            if (defined($service->{'retain_nonstatus_information'})) { push @{$clapi{STPL}}, "STPL;setparam;".$OPTION{'prefix'}.$service->{'name'}.";retain_nonstatus_information;".$service->{'retain_nonstatus_information'} };
            if (defined($service->{'stalking_options'})) { push @{$clapi{STPL}}, "STPL;setparam;".$OPTION{'prefix'}.$service->{'name'}.";stalking_options;".((ref $service->{'stalking_options'}  eq "ARRAY") ? join(",", @{$service->{'stalking_options'}}) : $service->{'stalking_options'}) };
            if (defined($service->{'failure_prediction_enabled'})) { push @{$clapi{STPL}}, "STPL;setparam;".$OPTION{'prefix'}.$service->{'name'}.";failure_prediction_enabled;".$service->{'failure_prediction_enabled'} };
            if (defined($service->{'event_handler'})) {
                my ($handler_command, $handler_command_arguments) = split('!', (ref $service->{'event_handler'} eq "Nagios::Command") ? ${$service->{'event_handler'}}{'command_name'} : $service->{'event_handler'}, 2);
                if (defined($handler_command) && $handler_command ne "") { push @{$clapi{STPL}}, "STPL;setparam;".$OPTION{'prefix'}.$service->{'name'}.";event_handler;".$OPTION{'prefix'}.$handler_command };
                if (defined($handler_command_arguments) && $handler_command_arguments ne "") {
                    if ($OPTION{'prefix'} ne "") {
                        foreach my $macro (keys %resource_macros) {
                            $handler_command_arguments =~  s/\$$macro\$/\$$OPTION{'prefix'}$macro\$/g;
                        }
                    }
                    push @{$clapi{STPL}}, "STPL;setparam;".$OPTION{'prefix'}.$service->{'name'}.";event_handler_arguments;!".$handler_command_arguments
                }
            }
            if (defined($service->{'event_handler_enabled'})) { push @{$clapi{STPL}}, "STPL;setparam;".$OPTION{'prefix'}.$service->{'name'}.";event_handler_enabled;".$service->{'event_handler_enabled'} };
            if (defined($service->{'notes'})) { push @{$clapi{STPL}}, "STPL;setparam;".$OPTION{'prefix'}.$service->{'name'}.";notes;".$service->{'notes'} };
            if (defined($service->{'notes_url'})) { push @{$clapi{STPL}}, "STPL;setparam;".$OPTION{'prefix'}.$service->{'name'}.";notes_url;".$service->{'notes_url'} };
            if (defined($service->{'action_url'})) { push @{$clapi{STPL}}, "STPL;setparam;".$OPTION{'prefix'}.$service->{'name'}.";action_url;".$service->{'action_url'} };
            if (defined($service->{'comment'})) { push @{$clapi{STPL}}, "STPL;setparam;".$OPTION{'prefix'}.$service->{'name'}.";comment;".$service->{'comment'} };
            if (defined($service->{'icon_image'})) { push @{$clapi{STPL}}, "STPL;setparam;".$OPTION{'prefix'}.$service->{'name'}.";icon_image;".$service->{'icon_image'} };
            if (defined($service->{'icon_image_alt'})) { push @{$clapi{STPL}}, "STPL;setparam;".$OPTION{'prefix'}.$service->{'name'}.";icon_image_alt;".$service->{'icon_image_alt'} };
            if (defined($service->{'recovery_notification_delay'})) { push @{$clapi{STPL}}, "STPL;setparam;".$OPTION{'prefix'}.$service->{'name'}.";recovery_notification_delay;".$service->{'recovery_notification_delay'} };
        
            # Custom macros handling
            foreach my $macro ($service->list_attributes()) {
                if ($macro =~ m/^_/ && $macro !~ m/SERVICE_ID/ && defined($service->{$macro})) {
                    $macro =~ s/_//;
                    push @{$clapi{STPL}}, "STPL;setmacro;".$OPTION{'prefix'}.$service->{'name'}.";".$macro.";".$service->{"_".$macro}.";0;";
                }
            }
            
            # Add contactgroups to service
            if (defined($service->{'contact_groups'})) {
                if (ref $service->{'contact_groups'}) { push @{$clapi{STPL}}, "STPL;setcontactgroup;".$OPTION{'prefix'}.$service->{'name'}.";".(join("|", (my @contactgroups = map { (ref $_ ne "Nagios::ContactGroup") ? $OPTION{'prefix'}.$_ : $OPTION{'prefix'}.$_->{'contactgroup_name'} } @{$service->{'contact_groups'}}))) };
                if (not ref $service->{'contact_groups'}) { push @{$clapi{STPL}}, "STPL;setcontactgroup;".$OPTION{'prefix'}.$service->{'name'}.";".$OPTION{'prefix'}.$service->{'contact_groups'} };
            }

            # Add contacts to service
            if (defined($service->{'contacts'})) {
                if (ref $service->{'contacts'}) { push @{$clapi{STPL}}, "STPL;setcontact;".$OPTION{'prefix'}.$service->{'name'}.";".(join("|", (my @contactgroups = map { (ref $_ ne "Nagios::Contact") ? $OPTION{'prefix'}.$_ : $OPTION{'prefix'}.$_->{'contact_name'} } @{$service->{'contacts'}}))) };
                if (not ref $service->{'contacts'}) { push @{$clapi{STPL}}, "STPL;setcontact;".$OPTION{'prefix'}.$service->{'name'}.";".$OPTION{'prefix'}.$service->{'contacts'} };
            }

            $service_exported{$service->{'name'}} = 1;
        } elsif (defined($service->{'host_name'}) && $service->{'host_name'} !~ m/^\_Module\_BAM/) {
            my @hosts;
            if (ref $service->{'host_name'}) { @hosts = @{$service->{'host_name'}} };
            if (not ref $service->{'host_name'}) { push @hosts, $service->{'host_name'} };
            
            foreach my $host (@hosts) {
                if (defined($service->{'service_description'})) { push @{$clapi{SERVICE}}, "SERVICE;ADD;".$host.";".$service->{'service_description'}.";".(defined($service->{'use'}) ? $OPTION{'prefix'}.$service->{'use'} : $OPTION{'default_stpl'}) };
                if (defined($service->{'is_volatile'})) { push @{$clapi{SERVICE}}, "SERVICE;setparam;".$host.";".$service->{'service_description'}.";is_volatile;".$service->{'is_volatile'} };
                if (defined($service->{'check_period'})) { push @{$clapi{SERVICE}}, "SERVICE;setparam;".$host.";".$service->{'service_description'}.";check_period;".((ref $service->{'check_period'} eq "Nagios::TimePeriod") ? $OPTION{'prefix'}.${$service->{'check_period'}}{'timeperiod_name'} : $OPTION{'prefix'}.$service->{'check_period'}) };
                if (defined($service->{'check_command'})) {
                    my ($check_command, $check_command_arguments) = split('!', (ref $service->{'check_command'} eq "Nagios::Command") ? ${$service->{'check_command'}}{'command_name'} : $service->{'check_command'}, 2);
                    if (defined($check_command) && $check_command ne "") { push @{$clapi{SERVICE}}, "SERVICE;setparam;".$host.";".$service->{'service_description'}.";check_command;".$OPTION{'prefix'}.$check_command };
                    if (defined($check_command_arguments) && $check_command_arguments ne "") {
                        if ($OPTION{'prefix'} ne "") {
                        foreach my $macro (keys %resource_macros) {
                            $check_command_arguments =~  s/\$$macro\$/\$$OPTION{'prefix'}$macro\$/g;
                            }
                        }
                        push @{$clapi{SERVICE}}, "SERVICE;setparam;".$host.";".$service->{'service_description'}.";check_command_arguments;!".$check_command_arguments
                    }
                }
                if (defined($service->{'max_check_attempts'})) { push @{$clapi{SERVICE}}, "SERVICE;setparam;".$host.";".$service->{'service_description'}.";max_check_attempts;".$service->{'max_check_attempts'} };
                if (defined($service->{'check_interval'})) { push @{$clapi{SERVICE}}, "SERVICE;setparam;".$host.";".$service->{'service_description'}.";normal_check_interval;".$service->{'check_interval'} };
                if (defined($service->{'normal_check_interval'})) { push @{$clapi{SERVICE}}, "SERVICE;setparam;".$host.";".$service->{'service_description'}.";normal_check_interval;".$service->{'normal_check_interval'} };
                if (defined($service->{'retry_interval'})) { push @{$clapi{SERVICE}}, "SERVICE;setparam;".$host.";".$service->{'service_description'}.";retry_check_interval;".$service->{'retry_interval'} };
                if (defined($service->{'active_checks_enabled'})) { push @{$clapi{SERVICE}}, "SERVICE;setparam;".$host.";".$service->{'service_description'}.";active_checks_enabled;".$service->{'active_checks_enabled'} };
                if (defined($service->{'passive_checks_enabled'})) { push @{$clapi{SERVICE}}, "SERVICE;setparam;".$host.";".$service->{'service_description'}.";passive_checks_enabled;".$service->{'passive_checks_enabled'} };
                if (defined($service->{'notifications_enabled'})) { push @{$clapi{SERVICE}}, "SERVICE;setparam;".$host.";".$service->{'service_description'}.";notifications_enabled;".$service->{'notifications_enabled'} };
                if (defined($service->{'notification_interval'})) { push @{$clapi{SERVICE}}, "SERVICE;setparam;".$host.";".$service->{'service_description'}.";notification_interval;".$service->{'notification_interval'} };
                if (defined($service->{'notification_period'})) { push @{$clapi{SERVICE}}, "SERVICE;setparam;".$host.";".$service->{'service_description'}.";notification_period;".((ref $service->{'notification_period'} eq "Nagios::TimePeriod") ? $OPTION{'prefix'}.${$service->{'notification_period'}}{'timeperiod_name'} : $OPTION{'prefix'}.$service->{'notification_period'}) };
                if (defined($service->{'notification_options'})) { push @{$clapi{SERVICE}}, "SERVICE;setparam;".$host.";".$service->{'service_description'}.";notification_options;".((ref $service->{'notification_options'} eq "ARRAY") ? join(",", @{$service->{'notification_options'}}) : $service->{'notification_options'}) };
                if (defined($service->{'first_notification_delay'})) { push @{$clapi{SERVICE}}, "SERVICE;setparam;".$host.";".$service->{'service_description'}.";first_notification_delay;".$service->{'first_notification_delay'} };
                if (defined($service->{'parallelize_check'})) { push @{$clapi{SERVICE}}, "SERVICE;setparam;".$host.";".$service->{'service_description'}.";parallelize_check;".$service->{'parallelize_check'} };
                if (defined($service->{'obsess_over_service'})) { push @{$clapi{SERVICE}}, "SERVICE;setparam;".$host.";".$service->{'service_description'}.";obsess_over_service;".$service->{'obsess_over_service'} };
                if (defined($service->{'check_freshness'})) { push @{$clapi{SERVICE}}, "SERVICE;setparam;".$host.";".$service->{'service_description'}.";check_freshness;".$service->{'check_freshness'} };
                if (defined($service->{'freshness_threshold'})) { push @{$clapi{SERVICE}}, "SERVICE;setparam;".$host.";".$service->{'service_description'}.";freshness_threshold;".$service->{'freshness_threshold'} };
                if (defined($service->{'flap_detection_enabled'})) { push @{$clapi{SERVICE}}, "SERVICE;setparam;".$host.";".$service->{'service_description'}.";flap_detection_enabled;".$service->{'flap_detection_enabled'} };
                if (defined($service->{'low_flap_threshold'})) { push @{$clapi{SERVICE}}, "SERVICE;setparam;".$host.";".$service->{'service_description'}.";low_flap_threshold;".$service->{'low_flap_threshold'} };
                if (defined($service->{'high_flap_threshold'})) { push @{$clapi{SERVICE}}, "SERVICE;setparam;".$host.";".$service->{'service_description'}.";high_flap_threshold;".$service->{'high_flap_threshold'} };
                if (defined($service->{'process_perf_data'})) { push @{$clapi{SERVICE}}, "SERVICE;setparam;".$host.";".$service->{'service_description'}.";process_perf_data;".$service->{'process_perf_data'} };
                if (defined($service->{'retain_status_information'})) { push @{$clapi{SERVICE}}, "SERVICE;setparam;".$host.";".$service->{'service_description'}.";retain_status_information;".$service->{'retain_status_information'} };
                if (defined($service->{'retain_nonstatus_information'})) { push @{$clapi{SERVICE}}, "SERVICE;setparam;".$host.";".$service->{'service_description'}.";retain_nonstatus_information;".$service->{'retain_nonstatus_information'} };
                if (defined($service->{'stalking_options'})) { push @{$clapi{SERVICE}}, "SERVICE;setparam;".$host.";".$service->{'service_description'}.";stalking_options;".((ref $service->{'stalking_options'} eq "ARRAY") ? join(",", @{$service->{'stalking_options'}}) : $service->{'stalking_options'}) };
                if (defined($service->{'failure_prediction_enabled'})) { push @{$clapi{SERVICE}}, "SERVICE;setparam;".$host.";".$service->{'service_description'}.";failure_prediction_enabled;".$service->{'failure_prediction_enabled'} };
                if (defined($service->{'event_handler'})) {
                    my ($handler_command, $handler_command_arguments) = split('!', (ref $service->{'event_handler'} eq "Nagios::Command") ? ${$service->{'event_handler'}}{'command_name'} : $service->{'event_handler'}, 2);
                    if (defined($handler_command) && $handler_command ne "") { push @{$clapi{SERVICE}}, "SERVICE;setparam;".$host.";".$service->{'service_description'}.";event_handler;".$OPTION{'prefix'}.$handler_command };
                    if (defined($handler_command_arguments) && $handler_command_arguments ne "") {
                        if ($OPTION{'prefix'} ne "") {
                            foreach my $macro (keys %resource_macros) {
                                $handler_command_arguments =~  s/\$$macro\$/\$$OPTION{'prefix'}$macro\$/g;
                            }
                        }
                        push @{$clapi{SERVICE}}, "SERVICE;setparam;".$host.";".$service->{'service_description'}.";event_handler_arguments;!".$handler_command_arguments
                    }
                }
                if (defined($service->{'event_handler_enabled'})) { push @{$clapi{SERVICE}}, "SERVICE;setparam;".$host.";".$service->{'service_description'}.";event_handler_enabled;".$service->{'event_handler_enabled'} };
                if (defined($service->{'notes'})) { push @{$clapi{SERVICE}}, "SERVICE;setparam;".$host.";".$service->{'service_description'}.";notes;".$service->{'notes'} };
                if (defined($service->{'notes_url'})) { push @{$clapi{SERVICE}}, "SERVICE;setparam;".$host.";".$service->{'service_description'}.";notes_url;".$service->{'notes_url'} };
                if (defined($service->{'action_url'})) { push @{$clapi{SERVICE}}, "SERVICE;setparam;".$host.";".$service->{'service_description'}.";action_url;".$service->{'action_url'} };
                if (defined($service->{'comment'})) { push @{$clapi{SERVICE}}, "SERVICE;setparam;".$host.";".$service->{'service_description'}.";comment;".$service->{'comment'} };
                if (defined($service->{'icon_image'})) { push @{$clapi{SERVICE}}, "SERVICE;setparam;".$host.";".$service->{'service_description'}.";icon_image;".$service->{'icon_image'} };
                if (defined($service->{'icon_image_alt'})) { push @{$clapi{SERVICE}}, "SERVICE;setparam;".$host.";".$service->{'service_description'}.";icon_image_alt;".$service->{'icon_image_alt'} };
                if (defined($service->{'recovery_notification_delay'})) { push @{$clapi{SERVICE}}, "SERVICE;setparam;".$host.";".$service->{'service_description'}.";recovery_notification_delay;".$service->{'recovery_notification_delay'} };
            
                # Custom macros handling
                foreach my $macro ($service->list_attributes()) {
                    if ($macro =~ m/^_/ && $macro !~ m/SERVICE_ID/ && defined($service->{$macro})) {
                        $macro =~ s/_//;
                        push @{$clapi{SERVICE}}, "SERVICE;setmacro;".$host.";".$service->{'service_description'}.";".$macro.";".$service->{"_".$macro}.";0;";
                    }
                }

                # Add contactgroups to service
                if (defined($service->{'contact_groups'})) {
                    if (ref $service->{'contact_groups'}) { push @{$clapi{SERVICE}}, "SERVICE;setcontactgroup;".$host.";".$service->{'service_description'}.";".(join("|", (my @contactgroups = map { (ref $_ ne "Nagios::ContactGroup") ? $OPTION{'prefix'}.$_ : $OPTION{'prefix'}.$_->{'contactgroup_name'} } @{$service->{'contact_groups'}}))) };
                    if (not ref $service->{'contact_groups'}) { push @{$clapi{SERVICE}}, "SERVICE;setcontactgroup;".$host.";".$service->{'service_description'}.";".$OPTION{'prefix'}.$service->{'contact_groups'} };
                }

                # Add contacts to service
                if (defined($service->{'contacts'})) {
                    if (ref $service->{'contacts'}) { push @{$clapi{SERVICE}}, "SERVICE;setcontact;".$host.";".$service->{'service_description'}.";".(join("|", (my @contactgroups = map { (ref $_ ne "Nagios::Contact") ? $OPTION{'prefix'}.$_ : $OPTION{'prefix'}.$_->{'contact_name'} } @{$service->{'contacts'}}))) };
                    if (not ref $service->{'contacts'}) { push @{$clapi{SERVICE}}, "SERVICE;setcontact;".$host.";".$service->{'service_description'}.";".$OPTION{'prefix'}.$service->{'contacts'} };
                }
                
                # Add service to servicegroups
                if (defined($service->{'servicegroups'})) {
                    if (ref $service->{'servicegroups'}) {
                        foreach my $servicegroup (@{$service->{'servicegroups'}}) {
                            push @{$servicegroups{$servicegroup}}, $host.",".$service->{'service_description'};
                        }
                    } else {
                        push @{$servicegroups{$service->{'servicegroups'}}}, $host.",".$service->{'service_description'};
                    }
                }
            }
        }
        
        # Deploy services based on previous template on all hosts linked to hostgroup
        if (defined($service->{'hostgroup_name'})) {
            if (ref $service->{'hostgroup_name'}) {
                foreach my $hostgroup (@{$service->{'hostgroup_name'}}) {
                    $hostgroup = $objects->find_object($hostgroup, "Nagios::HostGroup");
                    next if (ref $hostgroup ne "Nagios::HostGroup");
                    if (defined($hostgroup->{'members'})) {
                        if (ref $hostgroup->{'members'}) {
                            foreach my $host (@{$hostgroup->{'members'}}) {
                                push @{$clapi{SERVICE}}, "SERVICE;ADD;".$host.";".$service->{'service_description'}.";".$OPTION{'prefix'}.$service->{'name'};
                            }
                        } else {
                            push @{$clapi{SERVICE}}, "SERVICE;ADD;".$hostgroup->{'members'}.";".$service->{'service_description'}.";".$OPTION{'prefix'}.$service->{'name'};
                        }
                    }
                    # Loop to add hosts from host definition
                    if (defined($hostgroup->{'hostgroup_name'}) && defined($hostgroups{$hostgroup->{'hostgroup_name'}})) {
                        foreach my $host (@{$hostgroups{$hostgroup->{'hostgroup_name'}}}) {
                            push @{$clapi{SERVICE}}, "SERVICE;ADD;".$host.";".$service->{'service_description'}.";".$OPTION{'prefix'}.$service->{'name'};
                        }
                    }
                }
            } else {
                my $hostgroup = $objects->find_object($service->{'hostgroup_name'}, "Nagios::HostGroup");
                next if (ref $hostgroup ne "Nagios::HostGroup");
                if (defined($hostgroup->{'members'})) {
                    if (ref $hostgroup->{'members'}) {
                        foreach my $host (@{$hostgroup->{'members'}}) {
                            push @{$clapi{SERVICE}}, "SERVICE;ADD;".$host.";".$service->{'service_description'}.";".$OPTION{'prefix'}.$service->{'name'};
                        }
                    } else {
                        push @{$clapi{SERVICE}}, "SERVICE;ADD;".$hostgroup->{'members'}.";".$service->{'service_description'}.";".$OPTION{'prefix'}.$service->{'name'};
                    }
                }
                # Loop to add hosts from host definition
                if (defined($hostgroup->{'hostgroup_name'}) && defined($hostgroups{$hostgroup->{'hostgroup_name'}})) {
                    foreach my $host (@{$hostgroups{$hostgroup->{'hostgroup_name'}}}) {
                        push @{$clapi{SERVICE}}, "SERVICE;ADD;".$host.";".$service->{'service_description'}.";".$OPTION{'prefix'}.$service->{'name'};
                    }
                }
            }
        }
    }
}

# Export Nagios hostservicegroups using Centreon CLAPI format
sub export_servicegroups {
    my @servicegroups_array = @_ ;

    foreach my $servicegroup (@servicegroups_array) {
        next if (!defined($servicegroup->{'servicegroup_name'}) || $servicegroup->{'servicegroup_name'} =~ m/centreon\-bam\-contactgroup|\_Module\_BAM/);
     
        my (%services_exported, $host_name, $service_description);
     
        push @{$clapi{SG}}, "SG;ADD;".$OPTION{'prefix'}.$servicegroup->{'servicegroup_name'}.";".$servicegroup->{'alias'};
        push @{$clapi{SG}}, "SG;setparam;".$OPTION{'prefix'}.$servicegroup->{'servicegroup_name'}.";sg_activate;1";

        # Loop to add services from servicegroups definition
        if (defined($servicegroup->{'members'})) {
            foreach my $members (@{$servicegroup->{'members'}}) {
                foreach my $element (@{$members}) {
                    if ($objects->find_object($element, "Nagios::Host")) {
                        $host_name = $element;
                    } elsif ($objects->find_object($element, "Nagios::Service")) {
                        $service_description = $element;
                    }
                }
                if (!defined($services_exported{$host_name.",".$service_description})) {
                    push @{$clapi{SG}}, "SG;addservice;".$OPTION{'prefix'}.$servicegroup->{'servicegroup_name'}.";".$host_name.",".$service_description;
                    $services_exported{$host_name.",".$service_description} = 1;
                }
            }
        }

        # Loop to add services from service definition
        if (defined($servicegroups{$servicegroup->{'servicegroup_name'}})) {
            foreach my $hostservice (@{$servicegroups{$servicegroup->{'servicegroup_name'}}}) {
                if (!defined($services_exported{$hostservice})) {
                    push @{$clapi{SG}}, "SG;addservice;".$OPTION{'prefix'}.$servicegroup->{'servicegroup_name'}.";".$hostservice;
                }
            }
        }
    }
}

# Load Nagios configuration from directory
$objects = Nagios::Object::Config->new(Version => $OPTION{'version'});

opendir (DIR, $OPTION{'config'}) or die $!;
while (my $file = readdir(DIR)) {
    if ($file =~ m/$OPTION{'filter'}/) {
        $objects->parse($OPTION{'config'}."/".$file);
    }
}
closedir DIR;

# Generate Centreon CLAPI commands
export_resources();
export_commands(@{$objects->{command_list}});
export_timeperiods(@{$objects->{timeperiod_list}});
export_contacts(@{$objects->{contact_list}});
export_contactgroups(@{$objects->{contactgroup_list}});
export_hosts(@{$objects->{host_list}});
export_hostgroups(@{$objects->{hostgroup_list}});
export_services(@{$objects->{service_list}});
export_servicegroups(@{$objects->{servicegroup_list}});

my %multi;
foreach (@{$clapi{RESOURCECFG}}) { print $_, "\n" if ! $multi{$_}++ };
foreach (@{$clapi{CMD}}) { print $_, "\n" if ! $multi{$_}++ };
foreach (@{$clapi{TP}}) { print $_, "\n" if ! $multi{$_}++ };
foreach (@{$clapi{CONTACT}}) { print $_, "\n" if ! $multi{$_}++ };
foreach (@{$clapi{CG}}) { print $_, "\n" if ! $multi{$_}++ };
foreach (@{$clapi{HTPL}}) { print $_, "\n" if ! $multi{$_}++ };
foreach (@{$clapi{HOST}}) { print $_, "\n" if ! $multi{$_}++ };
foreach (@{$clapi{HG}}) { print $_, "\n" if ! $multi{$_}++ };
foreach (@{$clapi{STPL}}) { print $_, "\n" if ! $multi{$_}++ };
foreach (@{$clapi{SERVICE}}) { print $_, "\n" if ! $multi{$_}++ };
foreach (@{$clapi{SG}}) { print $_, "\n" if ! $multi{$_}++ };
foreach (@{$clapi{CONTACT_SWITCH}}) { print $_, "\n" if ! $multi{$_}++ };

exit 0;
