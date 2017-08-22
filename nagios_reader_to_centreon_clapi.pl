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
use Nagios::Config;
use Nagios::Object::Config;

my $PROGNAME = $0;
my $VERSION = "2.2.0";
my %ERRORS = ("OK" => 0, "WARNING" => 1, "CRITICAL" => 2, "UNKNOWN" => 3, "PENDING" => 4);

my %OPTION = ("help"    => undef,
              "version" => '3',
              "poller"  => "Central",
              "prefix"  => "",
              "config"  => "/usr/local/nagios/etc/nagios.cfg");

#############################
# Control command line args #
#############################

Getopt::Long::Configure('bundling');
GetOptions(
    "h|help"        => \$OPTION{'help'},
    "V|version=s"   => \$OPTION{'version'},
    "P|poller=s"    => \$OPTION{'poller'},
    "p|prefix=s"    => \$OPTION{'prefix'},
    "C|config=s"    => \$OPTION{'config'}
);

# Global vars
my $objects;
my %contactgroups;
my %hostgroups;
my %servicegroups;
my %host_exported;
my %service_exported;
my %resource_macros;

#############
# Functions #
#############

sub print_usage () {
    print "Usage: ";
    print $PROGNAME."\n";
    print "    -C (--config)      Path to nagios.cfg file\n";
    print "    -V (--version)     Nagios version of the configuration files\n";
    print "    -P (--poller)      Name of the targeted poller\n";
    print "    -p (--prefix)      Add a prefix before commands, contacts, templates, etc.\n";
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
    exit $ERRORS{'OK'};
}

if (! -e $OPTION{'config'}) {
    printf ("File %s doesn't exist please specify path with '-C option'\n", $OPTION{'config'});
    exit $ERRORS{'WARNING'};
}

# Export Nagios resource macros
sub export_resources {
    my $resource_file;
    
    open(my $fh, '<', $OPTION{'config'}) or die "Can't open $OPTION{'config'}: $!";
    while (my $line = <$fh>) {
        chomp $line;
        $resource_file = ($line =~ m/resource_file=(.*)/msi)[0] if ($line =~ m/resource_file/);
    }
    close $fh;

    if (defined($resource_file)) {
        open($fh, '<', $resource_file) or die "Can't open $resource_file: $!";
        while (my $line = <$fh>) {
            chomp $line;
            my ($macro, $value) = split('=', $line, 2) if ($line =~ /=/);
            $macro =~ s/\$//g if defined($macro);
            $resource_macros{$macro} = $value if (defined($macro) && defined($value));
        }
        close $fh;

        foreach my $macro (keys %resource_macros) {
            printf ("RESOURCECFG;ADD;%s;%s;%s;\n", "\$".$OPTION{'prefix'}.$macro."\$", $resource_macros{$macro}, $OPTION{'poller'});
            printf ("RESOURCECFG;setparam;%s;activate;1\n", "\$".$OPTION{'prefix'}.$macro."\$");
        }
    }
}

# Export Nagios commands using Centreon CLAPI format
sub export_commands {
    my @commands_array = @_;
    my $command_type;

    foreach my $command (@commands_array) {
        next if ($command->command_name =~ m/bam|check_meta|meta_notify/);
        
        $command_type = "check";
        if ($command->command_name =~ m/notify/) {
            $command_type = "notif";
        } elsif ($command->command_name =~ m/^process\-service\-perfdata|^submit\-host\-check\-result|^submit\-service\-check\-result/) {
            $command_type = "misc";
        }
        
        foreach my $macro (keys %resource_macros) {
            $command->{'command_line'} =~  s/\$$macro\$/\$$OPTION{'prefix'}$macro\$/g;
        }

        printf ("CMD;ADD;%s;%s;%s\n", $OPTION{'prefix'}.$command->command_name, $command_type, $command->{'command_line'});
        printf ("CMD;setparam;%s;comment;%s\n", $OPTION{'prefix'}.$command->command_name, $command->{'comment'}) if (defined($command->{'comment'}));
    }
    
    return 0;
}

# Export Nagios timepriods using Centreon CLAPI format
sub export_timeperiods {
    my @timeperiods_array = @_ ;

    foreach my $timeperiod (@timeperiods_array) {
        next if ($timeperiod->name =~ m/centreon\-bam|meta\_timeperiod/);

        printf ("TP;ADD;%s;%s\n", $OPTION{'prefix'}.$timeperiod->name, $timeperiod->{'alias'});
        printf ("TP;setparam;%s;tp_sunday;%s\n", $OPTION{'prefix'}.$timeperiod->name, $timeperiod->{'sunday'}) if (defined($timeperiod->{'sunday'}));
        printf ("TP;setparam;%s;tp_monday;%s\n", $OPTION{'prefix'}.$timeperiod->name, $timeperiod->{'monday'}) if (defined($timeperiod->{'monday'}));
        printf ("TP;setparam;%s;tp_tuesday;%s\n", $OPTION{'prefix'}.$timeperiod->name, $timeperiod->{'tuesday'}) if (defined($timeperiod->{'tuesday'}));
        printf ("TP;setparam;%s;tp_wednesday;%s\n", $OPTION{'prefix'}.$timeperiod->name, $timeperiod->{'wednesday'}) if (defined($timeperiod->{'wednesday'}));
        printf ("TP;setparam;%s;tp_thursday;%s\n", $OPTION{'prefix'}.$timeperiod->name, $timeperiod->{'thursday'}) if (defined($timeperiod->{'thursday'}));
        printf ("TP;setparam;%s;tp_friday;%s\n", $OPTION{'prefix'}.$timeperiod->name, $timeperiod->{'friday'}) if (defined($timeperiod->{'friday'}));
        printf ("TP;setparam;%s;tp_saturday;%s\n", $OPTION{'prefix'}.$timeperiod->name, $timeperiod->{'saturday'}) if (defined($timeperiod->{'saturday'}));
    }

    return 0;
}

# Export Nagios contacts using Centreon CLAPI format
sub export_contacts {
    my @contacts_array = @_ ;

    foreach my $contact (@contacts_array) {
        next if ($contact->contact_name =~ m/centreon\-bam|\_Module\_BAM/);

        my $contact_fullname = $contact->{'alias'};
        $contact_fullname =~ s/ /_/g;
        printf ("CONTACT;ADD;%s;%s;%s;%s;0;0;en_US;local\n", $OPTION{'prefix'}.$contact_fullname, $OPTION{'prefix'}.$contact->name, (defined($contact->{'email'})) ? $contact->{'email'} : "", (defined($contact->{'pager'})) ? $contact->{'pager'} : "");
        printf ("CONTACT;setparam;%s;hostnotifperiod;%s\n", $OPTION{'prefix'}.$contact->name, (ref $contact->{'host_notification_period'} eq "Nagios::TimePeriod") ? $OPTION{'prefix'}.${$contact->{'host_notification_period'}}{'timeperiod_name'} : $OPTION{'prefix'}.$contact->{'host_notification_period'}) if (defined($contact->{'host_notification_period'}));
        printf ("CONTACT;setparam;%s;svcnotifperiod;%s\n", $OPTION{'prefix'}.$contact->name, (ref $contact->{'service_notification_period'} eq "Nagios::TimePeriod") ? $OPTION{'prefix'}.${$contact->{'service_notification_period'}}{'timeperiod_name'} : $OPTION{'prefix'}.$contact->{'service_notification_period'}) if (defined($contact->{'service_notification_period'}));
        printf ("CONTACT;setparam;%s;hostnotifopt;%s\n", $OPTION{'prefix'}.$contact->name, (ref $contact->{'host_notification_options'} eq "ARRAY") ? join(",", @{$contact->{'host_notification_options'}}) : $contact->{'host_notification_options'}) if (defined($contact->{'host_notification_options'}));
		printf ("CONTACT;setparam;%s;servicenotifopt;%s\n", $OPTION{'prefix'}.$contact->name, (ref $contact->{'service_notification_options'} eq "ARRAY") ? join(",", @{$contact->{'service_notification_options'}}) : $contact->{'service_notification_options'}) if (defined($contact->{'service_notification_options'}));
        printf ("CONTACT;setparam;%s;contact_enable_notifications;%s\n", $OPTION{'prefix'}.$contact->name, $contact->{'host_notifications_enabled'}) if (defined($contact->{'host_notifications_enabled'}));
        printf ("CONTACT;setparam;%s;hostnotifcmd;%s\n", $OPTION{'prefix'}.$contact->name, join("|", (my @hostnotifcmd = map { $OPTION{'prefix'}.$_->name } @{$contact->{'host_notification_commands'}}))) if (defined($contact->{'host_notification_commands'}));
        printf ("CONTACT;setparam;%s;svcnotifcmd;%s\n", $OPTION{'prefix'}.$contact->name, join("|", (my @svcnotifcmd = map { $OPTION{'prefix'}.$_->name } @{$contact->{'service_notification_commands'}}))) if (defined($contact->{'service_notification_commands'}));
        printf ("CONTACT;setparam;%s;address1;%s\n", $OPTION{'prefix'}.$contact->name, $contact->{'address1'}) if (defined($contact->{'address1'}));
        printf ("CONTACT;setparam;%s;address2;%s\n", $OPTION{'prefix'}.$contact->name, $contact->{'address2'}) if (defined($contact->{'address2'}));
        printf ("CONTACT;setparam;%s;address3;%s\n", $OPTION{'prefix'}.$contact->name, $contact->{'address3'}) if (defined($contact->{'address3'}));
        printf ("CONTACT;setparam;%s;address4;%s\n", $OPTION{'prefix'}.$contact->name, $contact->{'address4'}) if (defined($contact->{'address4'}));
        printf ("CONTACT;setparam;%s;address5;%s\n", $OPTION{'prefix'}.$contact->name, $contact->{'address5'}) if (defined($contact->{'address5'}));
        printf ("CONTACT;setparam;%s;address6;%s\n", $OPTION{'prefix'}.$contact->name, $contact->{'address6'}) if (defined($contact->{'address6'}));
        printf ("CONTACT;setparam;%s;register;%s\n", $OPTION{'prefix'}.$contact->name, (defined($contact->register) ? $contact->register : 0));
        printf ("CONTACT;setparam;%s;comment;%s\n", $OPTION{'prefix'}.$contact->name, $contact->{'comment'}) if (defined($contact->{'comment'}));
        printf ("CONTACT;setparam;%s;contact_activate;1\n", $OPTION{'prefix'}.$contact->name);
        if (defined($contact->{'timezone'})) {
            my $timezone = $contact->{'timezone'};
            $timezone =~ s/://g;
            printf ("CONTACT;setparam;%s;timezone;%s\n", $OPTION{'prefix'}.$contact->name, $timezone);
        }
        
        # Add contact to contactgroups
        if (defined($contact->contactgroups) && @{$contact->contactgroups}) {
            foreach my $contactgroup (@{$contact->contactgroups}) {
                foreach my $contact (@{$contactgroup->members}) {
                    push @{$contactgroups{$contactgroup->contactgroup_name}}, $contact->name;
                }
            }
        }
    }
    
    return 0;
}

# Export Nagios contactgroups using Centreon CLAPI format
sub export_contactgroups {
    my @contactgroups_array = @_ ;

    foreach my $contactgroup (@contactgroups_array) {
        next if ($contactgroup->name =~ m/centreon\-bam\-contactgroup|\_Module\_BAM/);

        my %contacts_exported;

        printf ("CG;ADD;%s;%s\n", $OPTION{'prefix'}.$contactgroup->name, $contactgroup->{'alias'});
        printf ("CG;setparam;%s;cg_activate;1\n", $OPTION{'prefix'}.$contactgroup->name);
        printf ("CG;setparam;%s;cg_type;local\n", $OPTION{'prefix'}.$contactgroup->name);

        # Loop to add contacts from contactgroup definition
        if (defined($contactgroup->members )) {
            foreach my $contact (@{$contactgroup->members}) {
                if (!defined($contacts_exported{$contact->name})) {
                    printf ("CG;addcontact;%s;%s\n", $OPTION{'prefix'}.$contactgroup->name, $OPTION{'prefix'}.$contact->name);
                    $contacts_exported{$contact->name} = 1;
                }
            }
        }
        
        # Loop to add contacts from contact definition
        if (defined($contactgroups{$contactgroup->name} )) {
            foreach my $contact (@{$contactgroups{$contactgroup->name}}) {
                if (!defined ($contacts_exported{$contact})) {
                    printf ("CG;addcontact;%s;%s\n", $OPTION{'prefix'}.$contactgroup->name, $OPTION{'prefix'}.$contact);
                }
            }
        }
    }

    return 0;
}

# Export Nagios hosts and templates of hosts using Centreon CLAPI format
sub export_hosts {
    my @hosts_array = @_;
    my @templates;

    foreach my $host (@hosts_array) {
        # If the host uses templates, we export the templates first
        if (defined($host->{'use'})) {
            @templates = split(',', $host->{'use'});

            foreach my $template (@templates) {
                next if (defined($host_exported{$template}));
                export_hosts($objects->find_object($template, "Nagios::Host"));
            }
        }

        if (defined($host->name) && ($host->name !~ m/\_Module\_BAM|\_Module\_Meta/) && !defined($host_exported{$host->name})) {
            my $type = "HOST";
            my $prefix = $OPTION{'prefix'};
            
            if (!defined($host->register) || $host->register == 0 || !defined($host->{'address'})) {
                printf ("HTPL;ADD;%s;%s;;%s;;\n", $prefix.$host->name, (defined($host->{'alias'}) ? $host->{'alias'} : $host->name), ((@templates) ? join("|", (my @template = map { $OPTION{'prefix'}.$_ } @templates)) : "generic-active-host-custom"));
                $type = "HTPL";
            } else {
                printf ("HOST;ADD;%s;%s;%s;%s;%s;\n", $host->name, (defined($host->{'alias'}) ? $host->{'alias'} : $host->name), $host->{'address'}, ((@templates) ? join("|", (my @template = map { $OPTION{'prefix'}.$_ } @templates)) : "generic-active-host-custom"), $OPTION{'poller'});
                $prefix = "";
            }
            printf ("%s;setparam;%s;2d_coords;%s\n", $type, $prefix.$host->name, $host->{'2d_coords'}) if (defined($host->{'2d_coords'}));
            printf ("%s;setparam;%s;3d_coords;%s\n", $type, $prefix.$host->name, $host->{'3d_coords'}) if (defined($host->{'3d_coords'}));
            printf ("%s;setparam;%s;3d_coords;%s\n", $type, $prefix.$host->name, $host->{'3d_coords'}) if (defined($host->{'3d_coords'}));
            printf ("%s;setparam;%s;action_url;%s\n", $type, $prefix.$host->name, $host->{'action_url'}) if (defined($host->{'action_url'}));
            printf ("%s;setparam;%s;active_checks_enabled;%s\n", $type, $prefix.$host->name, $host->{'active_checks_enabled'}) if (defined($host->{'active_checks_enabled'}));
            if (defined($host->{'check_command'})) {
                my ($check_command, $check_command_arguments) = split('!', $host->{'check_command'}, 2);
                printf ("%s;setparam;%s;check_command;%s\n", $type, $prefix.$host->name, $OPTION{'prefix'}.$check_command) if (defined($check_command) && $check_command ne "");
                printf ("%s;setparam;%s;check_command_arguments;!%s\n", $type, $prefix.$host->name, $check_command_arguments) if (defined($check_command_arguments) && $check_command_arguments ne "");
            }
            printf ("%s;setparam;%s;check_interval;%s\n", $type, $prefix.$host->name, $host->{'check_interval'}) if (defined($host->{'check_interval'}));
            printf ("%s;setparam;%s;check_interval;%s\n", $type, $prefix.$host->name, $host->{'normal_check_interval'}) if (defined($host->{'normal_check_interval'}));
            printf ("%s;setparam;%s;check_freshness;%s\n", $type, $prefix.$host->name, $host->{'check_freshness'}) if (defined($host->{'check_freshness'}));
            printf ("%s;setparam;%s;freshness_threshold;%s\n", $type, $prefix.$host->name, $host->{'freshness_threshold'}) if (defined($host->{'freshness_threshold'}));
            printf ("%s;setparam;%s;check_period;%s\n", $type, $prefix.$host->name, (ref $host->{'check_period'} eq "Nagios::TimePeriod") ? $OPTION{'prefix'}.${$host->{'check_period'}}{'timeperiod_name'} : $OPTION{'prefix'}.$host->{'check_period'}) if (defined($host->{'check_period'}));
            printf ("%s;setparam;%s;event_handler;%s\n", $type, $prefix.$host->name, $host->{'event_handler'}) if (defined($host->{'event_handler'}));
            printf ("%s;setparam;%s;event_handler_enabled;%s\n", $type, $prefix.$host->name, $host->{'event_handler_enabled'}) if (defined($host->{'event_handler_enabled'}));
            #Not in 2.8.x printf ("%s;setparam;%s;failure_prediction_enabled;%s\n", $type, $prefix.$host->name, $host->{'failure_prediction_enabled'}) if (defined($host->{'failure_prediction_enabled'}));
            printf ("%s;setparam;%s;first_notification_delay;%s\n", $type, $prefix.$host->name, $host->{'first_notification_delay'}) if (defined($host->{'first_notification_delay'}));
            printf ("%s;setparam;%s;flap_detection_enabled;%s\n", $type, $prefix.$host->name, $host->{'flap_detection_enabled'}) if (defined($host->{'flap_detection_enabled'}));
            printf ("%s;setparam;%s;low_flap_threshold;%s\n", $type, $prefix.$host->name, $host->{'low_flap_threshold'}) if (defined($host->{'low_flap_threshold'}));
            printf ("%s;setparam;%s;high_flap_threshold;%s\n", $type, $prefix.$host->name, $host->{'high_flap_threshold'}) if (defined($host->{'high_flap_threshold'}));
            printf ("%s;setparam;%s;max_check_attempts;%s\n", $type, $prefix.$host->name, $host->{'max_check_attempts'}) if (defined($host->{'max_check_attempts'}));
            printf ("%s;setparam;%s;notes;%s\n", $type, $prefix.$host->name, $host->{'notes'}) if (defined($host->{'notes'}));
            printf ("%s;setparam;%s;notes_url;%s\n", $type, $prefix.$host->name, $host->{'notes_url'}) if (defined($host->{'notes_url'}));
            printf ("%s;setparam;%s;action_url;%s\n", $type, $prefix.$host->name, $host->{'action_url'}) if (defined($host->{'action_url'}));
            printf ("%s;setparam;%s;notifications_enabled;%s\n", $type, $prefix.$host->name, $host->{'notifications_enabled'}) if (defined($host->{'notifications_enabled'}));
            printf ("%s;setparam;%s;notification_interval;%s\n", $type, $prefix.$host->name, $host->{'notification_interval'}) if (defined($host->{'notification_interval'}));
		    printf ("%s;setparam;%s;notification_options;%s\n", $type, $prefix.$host->name, (ref $host->{'notification_options'} eq "ARRAY") ? join(",", @{$host->{'notification_options'}}) : $host->{'notification_options'}) if (defined($host->{'notification_options'}));
            printf ("%s;setparam;%s;notification_period;%s\n", $type, $prefix.$host->name, (ref $host->{'notification_period'} eq "Nagios::TimePeriod") ? $OPTION{'prefix'}.${$host->{'notification_period'}}{'timeperiod_name'} : $OPTION{'prefix'}.$host->{'notification_period'}) if (defined($host->{'notification_period'}));
            printf ("%s;setparam;%s;obsess_over_host;%s\n", $type, $prefix.$host->name, $host->{'obsess_over_host'}) if (defined($host->{'obsess_over_host'}));
            printf ("%s;setparam;%s;passive_checks_enabled;%s\n", $type, $prefix.$host->name, $host->{'passive_checks_enabled'}) if (defined($host->{'passive_checks_enabled'}));
            printf ("%s;setparam;%s;process_perf_data;%s\n", $type, $prefix.$host->name, $host->{'process_perf_data'}) if (defined($host->{'process_perf_data'}));
            printf ("%s;setparam;%s;retain_nonstatus_information;%s\n", $type, $prefix.$host->name, $host->{'retain_nonstatus_information'}) if (defined($host->{'retain_nonstatus_information'}));
            printf ("%s;setparam;%s;retain_status_information;%s\n", $type, $prefix.$host->name, $host->{'retain_status_information'}) if (defined($host->{'retain_status_information'}));
            printf ("%s;setparam;%s;retry_check_interval;%s\n", $type, $prefix.$host->name, $host->{'retry_interval'}) if (defined($host->{'retry_interval'}));
            printf ("%s;setparam;%s;stalking_options;%s\n", $type, $prefix.$host->name, (ref $host->{'stalking_options'} eq "ARRAY") ? join(",", @{$host->{'stalking_options'}}) : $host->{'stalking_options'}) if (defined($host->{'stalking_options'}));
            if (defined($host->{'event_handler'})) {
                my ($handler_command, $handler_command_arguments) = split('!', $host->{'event_handler'}, 2);
                printf ("%s;setparam;%s;event_handler;%s\n", $type, $prefix.$host->name, $OPTION{'prefix'}.$handler_command) if (defined($handler_command) && $handler_command ne "");
                printf ("%s;setparam;%s;event_handler_arguments;!%s\n", $type, $prefix.$host->name, $handler_command_arguments) if (defined($handler_command_arguments) && $handler_command_arguments ne "");
            }
            #printf ("%s;setparam;%s;icon_image;%s\n", $type, $prefix.$host->name, $host->{'icon_image'}) if (defined($host->{'icon_image'}));
            printf ("%s;setparam;%s;icon_image_alt;%s\n", $type, $prefix.$host->name, $host->{'icon_image_alt'}) if (defined($host->{'icon_image_alt'}));
            #printf ("%s;setparam;%s;statusmap_image;%s\n", $type, $prefix.$host->name, $host->{'statusmap_image'}) if (defined($host->{'statusmap_image'}));
            printf ("%s;setparam;%s;vrml_image;%s\n", $type, $prefix.$host->name, $host->{'vrml_image'}) if (defined($host->{'vrml_image'}));
            printf ("%s;setparam;%s;recovery_notification_delay;%s\n", $type, $prefix.$host->name, $host->{'recovery_notification_delay'}) if (defined($host->{'recovery_notification_delay'}));
            printf ("%s;setparam;%s;snmp_version;%s\n", $type, $prefix.$host->name, $host->{'_SNMPVERSION'}) if (defined($host->{'_SNMPVERSION'}));
            printf ("%s;setparam;%s;snmp_community;%s\n", $type, $prefix.$host->name, $host->{'_SNMPCOMMUNITY'}) if (defined($host->{'_SNMPCOMMUNITY'}));
            if (defined($host->{'timezone'})) {
                my $timezone = $host->{'timezone'};
                $timezone =~ s/://g;
                printf ("%s;setparam;%s;timezone;%s\n", $type, $prefix.$host->name, $timezone);
            }

            # Add parents
            if (defined($host->{'parents'})) {
                foreach my $parent (@{$host->parents}) {
                    export_hosts($objects->find_object($parent->name, "Nagios::Host")) if (!defined($host_exported{$parent->name}));
                }
                printf ("%s;setparent;%s;%s\n", $type, $prefix.$host->name, join("|", (my @parents = map { $_->name } @{$host->{'parents'}})));
            }
            
            # Macros handling
            foreach my $macro ($host->list_attributes()) {
                if ($macro =~ m/^_/ && $macro !~ m/SNMP|HOST_ID/ && defined($host->{$macro})) {
                    $macro =~ s/_//;
                    printf ("%s;setmacro;%s;%s;%s;0;\n", $type, $prefix.$host->name, $macro, $host->{"_".$macro});
                }
            }

            # Add contactgroups to host
            if (defined($host->{'contact_groups'})) {# && $host->{'contact_groups'} != "") {
                printf ("%s;setcontactgroup;%s;%s\n", $type, $prefix.$host->name, join("|", (my @contactgroups = map { (ref $_ ne "Nagios::ContactGroup") ? $OPTION{'prefix'}.$_ : $OPTION{'prefix'}.$_->{'contactgroup_name'} } @{$host->{'contact_groups'}}))) if (ref $host->{'contact_groups'});
                printf ("%s;setcontactgroup;%s;%s\n", $type, $prefix.$host->name, $OPTION{'prefix'}.$host->{'contact_groups'}) if (not ref $host->{'contact_groups'});
            }

            # Add contacts to host
            if (defined($host->{'contacts'})) {# && $host->{'contacts'} != "") {
                printf ("%s;setcontact;%s;%s\n", $type, $prefix.$host->name, join("|", (my @contactgroups = map { (ref $_ ne "Nagios::Contact") ? $OPTION{'prefix'}.$_ : $OPTION{'prefix'}.$_->{'contact_name'} } @{$host->{'contacts'}}))) if (ref $host->{'contacts'});
                printf ("%s;setcontact;%s;%s\n", $type, $prefix.$host->name, $OPTION{'prefix'}.$host->{'contacts'}) if (not ref $host->{'contacts'}); 
            }

            # Add host to hostgroups
            if (defined ($host->hostgroups)) {
                foreach my $hostgroup (@{$host->hostgroups}) {
                    push @{$hostgroups{$hostgroup->{'hostgroup_name'}}}, $host->name;
                }
            }

            # To do not export twice template
            $host_exported{$host->name} = 1;
        }
    }
}

# Export Nagios hostgroups using Centreon CLAPI format
sub export_hostgroups {
    my @hostgroups_array = @_ ;

    foreach my $hostgroup (@hostgroups_array) {
        next if ($hostgroup->{'hostgroup_name'} =~ m/centreon\-bam\-contactgroup|\_Module\_BAM/);

        my %hostgroups_exported;

        printf ("HG;ADD;%s;%s\n", $OPTION{'prefix'}.$hostgroup->{'hostgroup_name'}, $hostgroup->{'alias'});
        printf ("HG;setparam;%s;hg_activate;1\n", $OPTION{'prefix'}.$hostgroup->{'hostgroup_name'});

        # Loop to add hosts from hostgroups definition
        if (defined($hostgroup->members)) {
            foreach my $host (@{$hostgroup->members}) {
                if (!defined($hostgroups_exported{$host->host_name})) {
                    printf ("HG;addhost;%s;%s\n", $OPTION{'prefix'}.$hostgroup->{'hostgroup_name'}, $host->host_name);
                    $hostgroups_exported{$host->host_name} = 1;
                }
            }
        }

        # Loop to add hosts from host definition
        if (defined($hostgroups{$hostgroup->{'hostgroup_name'}})) {
            foreach my $host (@{$hostgroups{$hostgroup->{'hostgroup_name'}}}) {
                if (!defined($hostgroups_exported{$host})) {
                    printf ("HG;addhost;%s;%s\n", $OPTION{'prefix'}.$hostgroup->{'hostgroup_name'}, $host);
                }
            }
        }
    }
}

# Export Nagios host dependency using Centreon CLAPI format
sub export_hostdependencies {
    my @hostdependencies_array = @_ ;

    foreach my $hostdependencie (@hostdependencies_array) {        
        # Hostgroup dependancy
        if ((@{$hostdependencie->dependent_hostgroup_name} != 0) && (@{$hostdependencie->{'hostgroup_name'}} != 0)) {
            printf ("DEP;ADD;%s;%s;HG;%s\n", $OPTION{'prefix'}.$hostdependencie->name, $hostdependencie->name, join("|", (my @hostdependencies = map { $_->{'hostgroup_name'} } @{$hostdependencie->{'hostgroup_name'}})));
            
            foreach (@{$hostdependencie->dependent_hostgroup_name}) {
                printf ("DEP;addparent;%s;%s\n", $OPTION{'prefix'}.$hostdependencie->name, $_->{'hostgroup_name'});
            }
        }
        # Host dependancy
        if ((@{$hostdependencie->dependent_host_name} != 0) && (@{$hostdependencie->host_name} != 0)) {
            printf ("DEP;ADD;%s;%s;HOST;%s\n", $OPTION{'prefix'}.$hostdependencie->name, $hostdependencie->name, join("|", (my @hostdependencies = map { $_->name } @{$hostdependencie->host_name})));
        
            foreach (@{$hostdependencie->dependent_host_name}) {
                printf ("DEP;addparent;%s;%s\n", $OPTION{'prefix'}.$hostdependencie->name, $_);
            }
        }
    }
}

# Export Nagios services and templates of services using Centreon CLAPI format
sub export_services {
    my @services_array = @_;

    foreach my $service (@services_array) {
        # If the service uses a template, we export the template first
        if (defined($service->use)) {
            export_services($objects->find_object($service->use, "Nagios::Service"));
        }

        if (defined($service->name) && ($service->name !~ m/^ba\_|^meta\_/) && (defined($service->host_name) || !defined($service_exported{$service->name}))) {
            my $service_name;
            my $type = "SERVICE";

            if (defined($service->{'hostgroup_name'})) {
                # Create template of service for services by hostgroups
                $type = "STPL";
                $service_name = $OPTION{'prefix'}."Service-By-Hg-".$service->name;
            } elsif (!defined($service->register) || $service->register == 0) {
                # Create template
                $type = "STPL";
            } else {
                $type = "SERVICE";
            }

            if ($type eq "STPL") {
                printf ("STPL;ADD;%s;%s;%s\n", (defined($service_name) ? $service_name : $OPTION{'prefix'}.$service->name), (defined($service_name) ? $service_name : $service->{'service_description'}), (defined($service->use) ? $OPTION{'prefix'}.$service->use : "generic-active-service-custom"));
                printf ("STPL;setparam;%s;is_volatile;%s\n", (defined($service_name) ? $service_name : $OPTION{'prefix'}.$service->name), $service->{'is_volatile'}) if (defined($service->{'is_volatile'}));
                printf ("STPL;setparam;%s;check_period;%s\n", (defined($service_name) ? $service_name : $OPTION{'prefix'}.$service->name), (ref $service->{'check_period'} eq "Nagios::TimePeriod") ? $OPTION{'prefix'}.${$service->{'check_period'}}{'timeperiod_name'} : $OPTION{'prefix'}.$service->{'check_period'}) if (defined($service->{'check_period'}));
                if (defined($service->{'check_command'})) {
                    my ($check_command, $check_command_arguments) = split('!', (ref $service->{'check_command'} eq "Nagios::Command") ? ${$service->{'check_command'}}{'command_name'} : $service->{'check_command'}, 2);
                    printf ("STPL;setparam;%s;check_command;%s\n", (defined($service_name) ? $service_name : $OPTION{'prefix'}.$service->name), $OPTION{'prefix'}.$check_command) if (defined($check_command) && $check_command ne "");
                    printf ("STPL;setparam;%s;check_command_arguments;!%s\n", (defined($service_name) ? $service_name : $OPTION{'prefix'}.$service->name), $check_command_arguments) if (defined($check_command_arguments) && $check_command_arguments ne "");
                }
                printf ("STPL;setparam;%s;max_check_attempts;%s\n", (defined($service_name) ? $service_name : $OPTION{'prefix'}.$service->name), $service->{'max_check_attempts'}) if (defined($service->{'max_check_attempts'}));
                printf ("STPL;setparam;%s;normal_check_interval;%s\n", (defined($service_name) ? $service_name : $OPTION{'prefix'}.$service->name), $service->{'check_interval'}) if (defined($service->{'check_interval'}));
                printf ("STPL;setparam;%s;normal_check_interval;%s\n", (defined($service_name) ? $service_name : $OPTION{'prefix'}.$service->name), $service->{'normal_check_interval'}) if (defined($service->{'normal_check_interval'}));
                printf ("STPL;setparam;%s;retry_check_interval;%s\n", (defined($service_name) ? $service_name : $OPTION{'prefix'}.$service->name), $service->{'retry_interval'}) if (defined($service->{'retry_interval'}));
                printf ("STPL;setparam;%s;active_checks_enabled;%s\n", (defined($service_name) ? $service_name : $OPTION{'prefix'}.$service->name), $service->{'active_checks_enabled'}) if (defined($service->{'active_checks_enabled'}));
                printf ("STPL;setparam;%s;passive_checks_enabled;%s\n", (defined($service_name) ? $service_name : $OPTION{'prefix'}.$service->name), $service->{'passive_checks_enabled'}) if (defined($service->{'passive_checks_enabled'}));
                printf ("STPL;setparam;%s;notifications_enabled;%s\n", (defined($service_name) ? $service_name : $OPTION{'prefix'}.$service->name), $service->{'notifications_enabled'}) if (defined($service->{'notifications_enabled'}));
                printf ("STPL;setparam;%s;notification_interval;%s\n", (defined($service_name) ? $service_name : $OPTION{'prefix'}.$service->name), $service->{'notification_interval'}) if (defined($service->{'notification_interval'}));
                printf ("STPL;setparam;%s;notification_period;%s\n", (defined($service_name) ? $service_name : $OPTION{'prefix'}.$service->name), (ref $service->{'notification_period'} eq "Nagios::TimePeriod") ? $OPTION{'prefix'}.${$service->{'notification_period'}}{'timeperiod_name'} : $OPTION{'prefix'}.$service->{'notification_period'}) if (defined($service->{'notification_period'}));
                printf ("STPL;setparam;%s;notification_options;%s\n", (defined($service_name) ? $service_name : $OPTION{'prefix'}.$service->name), (ref $service->{'notification_options'}  eq "ARRAY") ? join(",", @{$service->{'notification_options'}}) : $service->{'notification_options'}) if (defined($service->{'notification_options'}));
                printf ("STPL;setparam;%s;first_notification_delay;%s\n", (defined($service_name) ? $service_name : $OPTION{'prefix'}.$service->name), $service->{'first_notification_delay'}) if (defined($service->{'first_notification_delay'}));
                printf ("STPL;setparam;%s;parallelize_check;%s\n", (defined($service_name) ? $service_name : $OPTION{'prefix'}.$service->name), $service->{'parallelize_check'}) if (defined($service->{'parallelize_check'}));
                printf ("STPL;setparam;%s;obsess_over_service;%s\n", (defined($service_name) ? $service_name : $OPTION{'prefix'}.$service->name), $service->{'obsess_over_service'}) if (defined($service->{'obsess_over_service'}));
                printf ("STPL;setparam;%s;check_freshness;%s\n", (defined($service_name) ? $service_name : $OPTION{'prefix'}.$service->name), $service->{'check_freshness'}) if (defined($service->{'check_freshness'}));
                printf ("STPL;setparam;%s;freshness_threshold;%s\n", (defined($service_name) ? $service_name : $OPTION{'prefix'}.$service->name), $service->{'freshness_threshold'}) if (defined($service->{'freshness_threshold'}));
                printf ("STPL;setparam;%s;flap_detection_enabled;%s\n", (defined($service_name) ? $service_name : $OPTION{'prefix'}.$service->name), $service->{'flap_detection_enabled'}) if (defined($service->{'flap_detection_enabled'}));
                printf ("STPL;setparam;%s;flap_detection_options;%s\n", (defined($service_name) ? $service_name : $OPTION{'prefix'}.$service->name), join(",", @{$service->{'flap_detection_options'}})) if (defined($service->{'flap_detection_options'}));
                printf ("STPL;setparam;%s;low_flap_threshold;%s\n", (defined($service_name) ? $service_name : $OPTION{'prefix'}.$service->name), $service->{'low_flap_threshold'}) if (defined($service->{'low_flap_threshold'}));
                printf ("STPL;setparam;%s;high_flap_threshold;%s\n", (defined($service_name) ? $service_name : $OPTION{'prefix'}.$service->name), $service->{'high_flap_threshold'}) if (defined($service->{'high_flap_threshold'}));
                printf ("STPL;setparam;%s;process_perf_data;%s\n", (defined($service_name) ? $service_name : $OPTION{'prefix'}.$service->name), $service->{'process_perf_data'}) if (defined($service->{'process_perf_data'}));
                printf ("STPL;setparam;%s;retain_status_information;%s\n", (defined($service_name) ? $service_name : $OPTION{'prefix'}.$service->name), $service->{'retain_status_information'}) if (defined($service->{'retain_status_information'}));
                printf ("STPL;setparam;%s;retain_nonstatus_information;%s\n", (defined($service_name) ? $service_name : $OPTION{'prefix'}.$service->name), $service->{'retain_nonstatus_information'}) if (defined($service->{'retain_nonstatus_information'}));
                printf ("STPL;setparam;%s;stalking_options;%s\n", (defined($service_name) ? $service_name : $OPTION{'prefix'}.$service->name), (ref $service->{'stalking_options'}  eq "ARRAY") ? join(",", @{$service->{'stalking_options'}}) : $service->{'stalking_options'}) if (defined($service->{'stalking_options'}));
                printf ("STPL;setparam;%s;failure_prediction_enabled;%s\n", (defined($service_name) ? $service_name : $OPTION{'prefix'}.$service->name), $service->{'failure_prediction_enabled'}) if (defined($service->{'failure_prediction_enabled'}));
                if (defined($service->{'event_handler'})) {
                    my ($handler_command, $handler_command_arguments) = split('!', (ref $service->{'event_handler'} eq "Nagios::Command") ? ${$service->{'event_handler'}}{'command_name'} : $service->{'event_handler'}, 2);
                    printf ("STPL;setparam;%s;event_handler;%s\n", (defined($service_name) ? $service_name : $OPTION{'prefix'}.$service->name), $OPTION{'prefix'}.$handler_command) if (defined($handler_command) && $handler_command ne "");
                    printf ("STPL;setparam;%s;event_handler_arguments;!%s\n", (defined($service_name) ? $service_name : $OPTION{'prefix'}.$service->name), $handler_command_arguments) if (defined($handler_command_arguments) && $handler_command_arguments ne "");
                }
                printf ("STPL;setparam;%s;event_handler_enabled;%s\n", (defined($service_name) ? $service_name : $OPTION{'prefix'}.$service->name), $service->{'event_handler_enabled'}) if (defined($service->{'event_handler_enabled'}));
                printf ("STPL;setparam;%s;notes;%s\n", (defined($service_name) ? $service_name : $OPTION{'prefix'}.$service->name), $service->{'notes'}) if (defined($service->{'notes'}));
                printf ("STPL;setparam;%s;notes_url;%s\n", (defined($service_name) ? $service_name : $OPTION{'prefix'}.$service->name), $service->{'notes_url'}) if (defined($service->{'notes_url'}));  
                printf ("STPL;setparam;%s;action_url;%s\n", (defined($service_name) ? $service_name : $OPTION{'prefix'}.$service->name), $service->{'action_url'}) if (defined($service->{'action_url'}));
                printf ("STPL;setparam;%s;comment;%s\n", (defined($service_name) ? $service_name : $OPTION{'prefix'}.$service->name), $service->{'comment'}) if (defined($service->{'comment'}));
                printf ("STPL;setparam;%s;icon_image;%s\n", (defined($service_name) ? $service_name : $OPTION{'prefix'}.$service->name), $service->{'icon_image'}) if (defined($service->{'icon_image'}));
                printf ("STPL;setparam;%s;icon_image_alt;%s\n", (defined($service_name) ? $service_name : $OPTION{'prefix'}.$service->name), $service->{'icon_image_alt'}) if (defined($service->{'icon_image_alt'}));
                printf ("STPL;setparam;%s;recovery_notification_delay;%s\n", (defined($service_name) ? $service_name : $OPTION{'prefix'}.$service->name), $service->{'recovery_notification_delay'}) if (defined($service->{'recovery_notification_delay'}));
            
                # Custom macros handling
                foreach my $macro ($service->list_attributes()) {
                    if ($macro =~ m/^_/ && $macro !~ m/SERVICE_ID/ && defined($service->{$macro})) {
                        $macro =~ s/_//;
                        printf ("STPL;setmacro;%s;%s;%s;0;\n", (defined($service_name) ? $service_name : $OPTION{'prefix'}.$service->name), $macro, $service->{"_".$macro});
                    }
                }
                
                # Add contactgroups to service
                if (defined($service->{'contact_groups'})) {# && $host->{'contact_groups'} != "") {
                    printf ("STPL;setcontactgroup;%s;%s\n", (defined($service_name) ? $service_name : $OPTION{'prefix'}.$service->name), join("|", (my @contactgroups = map { (ref $_ ne "Nagios::ContactGroup") ? $OPTION{'prefix'}.$_ : $OPTION{'prefix'}.$_->{'contactgroup_name'} } @{$service->{'contact_groups'}}))) if (ref $service->{'contact_groups'});
                    printf ("STPL;setcontactgroup;%s;%s\n", (defined($service_name) ? $service_name : $OPTION{'prefix'}.$service->name), $OPTION{'prefix'}.$service->{'contact_groups'}) if ($service->{'contact_groups'} and not ref $service->{'contact_groups'}); 
                }

                # Add contacts to service
                if (defined($service->{'contacts'})) {# && $host->{'contacts'} != "") {
                    printf ("STPL;setcontact;%s;%s\n", (defined($service_name) ? $service_name : $OPTION{'prefix'}.$service->name), join("|", (my @contactgroups = map { (ref $_ ne "Nagios::Contact") ? $OPTION{'prefix'}.$_ : $OPTION{'prefix'}.$_->{'contact_name'} } @{$service->{'contacts'}}))) if (ref $service->{'contacts'});
                    printf ("STPL;setcontact;%s;%s\n", (defined($service_name) ? $service_name : $OPTION{'prefix'}.$service->name), $OPTION{'prefix'}.$service->{'contacts'}) if (not ref $service->{'contacts'}); 
                }

                $service_exported{$service->name} = 1;
            } elsif ($type eq "SERVICE") {
                foreach my $host (@{$service->host_name}) {
                    printf ("SERVICE;ADD;%s;%s;%s\n", $host->host_name, $service->name, (defined($service->use) ? $OPTION{'prefix'}.$service->use : "generic-active-service-custom"));
                    printf ("SERVICE;setparam;%s;%s;is_volatile;%s\n", $host->host_name, $service->name, $service->{'is_volatile'}) if (defined($service->{'is_volatile'}));
                    printf ("SERVICE;setparam;%s;%s;check_period;%s\n", $host->host_name, $service->name, (ref $service->{'check_period'} eq "Nagios::TimePeriod") ? $OPTION{'prefix'}.${$service->{'check_period'}}{'timeperiod_name'} : $OPTION{'prefix'}.$service->{'check_period'}) if (defined($service->{'check_period'}));
                    if (defined($service->{'check_command'})) {
                        my ($check_command, $check_command_arguments) = split('!', (ref $service->{'check_command'} eq "Nagios::Command") ? ${$service->{'check_command'}}{'command_name'} : $service->{'check_command'}, 2);
                        printf ("SERVICE;setparam;%s;%s;check_command;%s\n", $host->host_name, $service->name, $OPTION{'prefix'}.$check_command) if (defined($check_command) && $check_command ne "");
                        printf ("SERVICE;setparam;%s;%s;check_command_arguments;!%s\n", $host->host_name, $service->name, $check_command_arguments) if (defined($check_command_arguments) && $check_command_arguments ne "");
                    }
                    printf ("SERVICE;setparam;%s;%s;max_check_attempts;%s\n", $host->host_name, $service->name, $service->{'max_check_attempts'}) if (defined($service->{'max_check_attempts'}));
                    printf ("SERVICE;setparam;%s;%s;normal_check_interval;%s\n", $host->host_name, $service->name, $service->{'check_interval'}) if (defined($service->{'check_interval'}));
                    printf ("SERVICE;setparam;%s;%s;normal_check_interval;%s\n", $host->host_name, $service->name, $service->{'normal_check_interval'}) if (defined($service->{'normal_check_interval'}));
                    printf ("SERVICE;setparam;%s;%s;retry_check_interval;%s\n", $host->host_name, $service->name, $service->{'retry_interval'}) if (defined($service->{'retry_interval'}));
                    printf ("SERVICE;setparam;%s;%s;active_checks_enabled;%s\n", $host->host_name, $service->name, $service->{'active_checks_enabled'}) if (defined($service->{'active_checks_enabled'}));
                    printf ("SERVICE;setparam;%s;%s;passive_checks_enabled;%s\n", $host->host_name, $service->name, $service->{'passive_checks_enabled'}) if (defined($service->{'passive_checks_enabled'}));
                    printf ("SERVICE;setparam;%s;%s;notifications_enabled;%s\n", $host->host_name, $service->name, $service->{'notifications_enabled'}) if (defined($service->{'notifications_enabled'}));
                    printf ("SERVICE;setparam;%s;%s;notification_interval;%s\n", $host->host_name, $service->name, $service->{'notification_interval'}) if (defined($service->{'notification_interval'}));
                    printf ("SERVICE;setparam;%s;%s;notification_period;%s\n", $host->host_name, $service->name, (ref $service->{'notification_period'} eq "Nagios::TimePeriod") ? $OPTION{'prefix'}.${$service->{'notification_period'}}{'timeperiod_name'} : $OPTION{'prefix'}.$service->{'notification_period'}) if (defined($service->{'notification_period'}));
                    printf ("SERVICE;setparam;%s;%s;notification_options;%s\n", $host->host_name, $service->name, (ref $service->{'notification_options'} eq "ARRAY") ? join(",", @{$service->{'notification_options'}}) : $service->{'notification_options'}) if (defined($service->{'notification_options'}));
                    printf ("SERVICE;setparam;%s;%s;first_notification_delay;%s\n", $host->host_name, $service->name, $service->{'first_notification_delay'}) if (defined($service->{'first_notification_delay'}));
                    printf ("SERVICE;setparam;%s;%s;parallelize_check;%s\n", $host->host_name, $service->name, $service->{'parallelize_check'}) if (defined($service->{'parallelize_check'}));
                    printf ("SERVICE;setparam;%s;%s;obsess_over_service;%s\n", $host->host_name, $service->name, $service->{'obsess_over_service'}) if (defined($service->{'obsess_over_service'}));
                    printf ("SERVICE;setparam;%s;%s;check_freshness;%s\n", $host->host_name, $service->name, $service->{'check_freshness'}) if (defined($service->{'check_freshness'}));
                    printf ("SERVICE;setparam;%s;%s;freshness_threshold;%s\n", $host->host_name, $service->name, $service->{'freshness_threshold'}) if (defined($service->{'freshness_threshold'}));
                    printf ("SERVICE;setparam;%s;%s;flap_detection_enabled;%s\n", $host->host_name, $service->name, $service->{'flap_detection_enabled'}) if (defined($service->{'flap_detection_enabled'}));
                    printf ("SERVICE;setparam;%s;%s;flap_detection_options;%s\n", $host->host_name, $service->name, join(",", @{$service->{'flap_detection_options'}})) if (defined($service->{'flap_detection_options'}));
                    printf ("SERVICE;setparam;%s;%s;low_flap_threshold;%s\n", $host->host_name, $service->name, $service->{'low_flap_threshold'}) if (defined($service->{'low_flap_threshold'}));
                    printf ("SERVICE;setparam;%s;%s;high_flap_threshold;%s\n", $host->host_name, $service->name, $service->{'high_flap_threshold'}) if (defined($service->{'high_flap_threshold'}));
                    printf ("SERVICE;setparam;%s;%s;process_perf_data;%s\n", $host->host_name, $service->name, $service->{'process_perf_data'}) if (defined($service->{'process_perf_data'}));
                    printf ("SERVICE;setparam;%s;%s;retain_status_information;%s\n", $host->host_name, $service->name, $service->{'retain_status_information'}) if (defined($service->{'retain_status_information'}));
                    printf ("SERVICE;setparam;%s;%s;retain_nonstatus_information;%s\n", $host->host_name, $service->name, $service->{'retain_nonstatus_information'}) if (defined($service->{'retain_nonstatus_information'}));
                    printf ("SERVICE;setparam;%s;%s;stalking_options;%s\n", $host->host_name, $service->name, (ref $service->{'stalking_options'} eq "ARRAY") ? join(",", @{$service->{'stalking_options'}}) : $service->{'stalking_options'}) if (defined($service->{'stalking_options'}));
                    printf ("SERVICE;setparam;%s;%s;failure_prediction_enabled;%s\n", $host->host_name, $service->name, $service->{'failure_prediction_enabled'}) if (defined($service->{'failure_prediction_enabled'}));
                    if (defined($service->{'event_handler'})) {
                        my ($handler_command, $handler_command_arguments) = split('!', (ref $service->{'event_handler'} eq "Nagios::Command") ? ${$service->{'event_handler'}}{'command_name'} : $service->{'event_handler'}, 2);
                        printf ("SERVICE;setparam;%s;%s;event_handler;%s\n", $host->host_name, $service->name, $OPTION{'prefix'}.$handler_command) if (defined($handler_command) && $handler_command ne "");
                        printf ("SERVICE;setparam;%s;%s;event_handler_arguments;!%s\n", $host->host_name, $service->name, $handler_command_arguments) if (defined($handler_command_arguments) && $handler_command_arguments ne "");
                    }
                    printf ("SERVICE;setparam;%s;%s;event_handler_enabled;%s\n", $host->host_name, $service->name, $service->{'event_handler_enabled'}) if (defined($service->{'event_handler_enabled'}));
                    printf ("SERVICE;setparam;%s;%s;notes;%s\n", $host->host_name, $service->name, $service->{'notes'}) if (defined($service->{'notes'}));
                    printf ("SERVICE;setparam;%s;%s;notes_url;%s\n", $host->host_name, $service->name, $service->{'notes_url'}) if (defined($service->{'notes_url'}));
                    printf ("SERVICE;setparam;%s;%s;action_url;%s\n", $host->host_name, $service->name, $service->{'action_url'}) if (defined($service->{'action_url'}));
                    printf ("SERVICE;setparam;%s;%s;comment;%s\n", $host->host_name, $service->name, $service->{'comment'}) if (defined($service->{'comment'}));
                    printf ("SERVICE;setparam;%s;%s;icon_image;%s\n", $host->host_name, $service->name, $service->{'icon_image'}) if (defined($service->{'icon_image'}));
                    printf ("SERVICE;setparam;%s;%s;icon_image_alt;%s\n", $host->host_name, $service->name, $service->{'icon_image_alt'}) if (defined($service->{'icon_image_alt'}));
                    printf ("SERVICE;setparam;%s;%s;recovery_notification_delay;%s\n", $host->host_name, $service->name, $service->{'recovery_notification_delay'}) if (defined($service->{'recovery_notification_delay'}));
                
                    # Custom macros handling
                    foreach my $macro ($service->list_attributes()) {
                        if ($macro =~ m/^_/ && $macro !~ m/SERVICE_ID/ && defined($service->{$macro})) {
                            $macro =~ s/_//;
                            printf ("SERVICE;setmacro;%s;%s;%s;%s;0;\n", $host->host_name, $service->name, $macro, $service->{"_".$macro});
                        }
                    }

                    # Add contactgroups to service
                    if (defined($service->{'contact_groups'})) {# && $host->{'contact_groups'} != "") {
                        printf ("SERVICE;setcontactgroup;%s;%s;%s\n", $host->host_name, $service->name, join("|", (my @contactgroups = map { (ref $_ ne "Nagios::ContactGroup") ? $OPTION{'prefix'}.$_ : $OPTION{'prefix'}.$_->{'contactgroup_name'} } @{$service->{'contact_groups'}}))) if (ref $service->{'contact_groups'});
                        printf ("SERVICE;setcontactgroup;%s;%s;%s\n", $host->host_name, $service->name, $OPTION{'prefix'}.$service->{'contact_groups'}) if (not ref $service->{'contact_groups'}); 
                    }

                    # Add contacts to service
                    if (defined($service->{'contacts'})) {# && $host->{'contacts'} != "") {
                        printf ("SERVICE;setcontact;%s;%s;%s\n", $host->host_name, $service->name, join("|", (my @contactgroups = map { (ref $_ ne "Nagios::Contact") ? $OPTION{'prefix'}.$_ : $OPTION{'prefix'}.$_->{'contact_name'} } @{$service->{'contacts'}}))) if (ref $service->{'contacts'});
                        printf ("SERVICE;setcontact;%s;%s;%s\n", $host->host_name, $service->name, $OPTION{'prefix'}.$service->{'contacts'}) if (not ref $service->{'contacts'}); 
                    }
                    
                    # Add service to servicegroups
                    if (defined($service->servicegroups)) {
                        foreach my $servicegroup (@{$service->servicegroups}) {
                            push @{$servicegroups{$servicegroup->{'servicegroup_name'}}}, $host->host_name.",".$service->name;
                        }
                    }
                }
            }
                        
            # Deploy services based on previous template on all hosts linked to hostgroup
            if (defined($service->{'hostgroup_name'})) {
                foreach my $hostgroup (@{$service->{'hostgroup_name'}}) {
                    foreach my $host (@{$hostgroup->members}) {
                        printf ("SERVICE;ADD;%s;%s;%s\n", $host->host_name, $service->name, $service_name);
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
        next if ($servicegroup->{'servicegroup_name'} =~ m/centreon\-bam\-contactgroup|\_Module\_BAM/);
     
        my (%services_exported, $host_name, $service_name);
     
        printf ("SG;ADD;%s;%s\n", $OPTION{'prefix'}.$servicegroup->{'servicegroup_name'}, $servicegroup->{'alias'});
        printf ("SG;setparam;%s;sg_activate;1\n", $OPTION{'prefix'}.$servicegroup->{'servicegroup_name'});

        # Loop to add services from servicegroups definition
        if (defined($servicegroup->members)) {
            foreach my $members (@{$servicegroup->members}) {
                foreach my $element (@{$members}) {
                    if ($element =~/Nagios::Host/) {
                        $host_name = $element->host_name;
                    } elsif ($element =~/Nagios::Service/) {
                        $service_name = $element->service_description;
                    }
                }
                if (!defined($services_exported{$host_name.",".$service_name})) {
                    printf ("SG;addservice;%s;%s,%s\n", $OPTION{'prefix'}.$servicegroup->{'servicegroup_name'}, $host_name, $service_name);
                    $services_exported{$host_name.",".$service_name} = 1;
                }
            }
        }

        # Loop to add services from service definition
        if (defined($servicegroups{$servicegroup->{'servicegroup_name'}})) {
            foreach my $service (@{$servicegroups{$servicegroup->{'servicegroup_name'}}}) {
                if (!defined($services_exported{$service})) {
                    printf ("SG;addservice;%s;%s\n", $OPTION{'prefix'}.$servicegroup->{'servicegroup_name'}, $service);
                }
            }
        }
    }
}

# Load Nagios configuration from main.cfg file
$objects = Nagios::Config->new(Filename => $OPTION{'config'}, Version => $OPTION{'version'}, force_relative_files => 0);

# Generate Centreon CLAPI commands
export_resources();
export_commands($objects->list_commands());
export_timeperiods($objects->list_timeperiods());
export_contacts($objects->list_contacts());
export_contactgroups($objects->list_contactgroups());
export_hosts($objects->list_hosts());
export_hostgroups($objects->list_hostgroups());
export_hostdependencies($objects->list_hostdependencies());
export_services($objects->list_services());
export_servicegroups($objects->list_servicegroups());

exit $ERRORS{'OK'};
