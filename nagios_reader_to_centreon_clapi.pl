#!/usr/bin/perl
#
# Copyright 2015 Centreon (http://www.centreon.com/)
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

use Getopt::Long;
use Nagios::Config;
use Nagios::Object::Config;

my $PROGNAME = $0;
my $VERSION = "1.0";
my %ERRORS = ( "OK" => 0, "WARNING" => 1, "CRITICAL" => 2, "UNKNOWN" => 3, "PENDING" => 4 );

my %OPTION = ( "help" => undef, 
			"version" => undef, 
			"config" => "/usr/local/nagios/etc/nagios.cfg" );

#############################
# Control command line args #
#############################

Getopt::Long::Configure('bundling');
GetOptions(
	"h|help"		=> \$OPTION{'help'},
    "V|version"		=> \$OPTION{'version'},
	"C|config=s"	=> \$OPTION{'config'}
);

if ( defined( $OPTION{'version'} ) ) {
	$PROGNAME =~ s/.\///;
    print "Program: $PROGNAME\n";
    print "Version: $VERSION\n";
    exit $ERRORS{'OK'};
}

if ( $OPTION{'help'} ) {
    print_help();
    exit $ERRORS{'OK'};
}

if ( ! -e $OPTION{'config'} ) {
	printf ( "File %s doesn't existplease specify path with '-C option'\n", $OPTION{'config'} );
	exit $ERRORS{'WARNING'};
}

# Global vars
my $default_poller = "Central";
my $objects;
my %contactgroups;
my %hostgroups;
my %hostTemplates_exported;
my %servicesgroups;
my %serviceTemplates_exported;

#############
# Functions #
#############

sub print_usage () {
    print "Usage: ";
    print $PROGNAME."\n";
    print "    -V (--version) Show script version\n";
    print "    -h (--help)    Usage help\n";
	print "    -C (--config)  Path to nagios.cfg file\n";
	print "\n";
}

sub print_help () {
		print "##############################################\n";
		print "#    Copyright (c) 2005-2015 Centreon        #\n";
		print "#    Bugs to http://github.com/centreon      #\n";
		print "##############################################\n";
    	print "\n";
    	print_usage();
    	print "\n";
}

# Export Nagios commands using Centreon CLAPI format
sub export_clapi_commands {
	my @commands_array = @_;
	my $command_type = "check";

	foreach my $command ( @commands_array ) {
		if ( $command->command_name =~ m/bam|check_meta|meta_notify/) {
			next;
		}
		if ( $command->command_name =~ m/notify/ ) {
			$command_type = "notif";
		} elsif ( $command->command_name =~ m/process\-service\-perfdata|submit\-host\-check\-result|submit\-service\-check\-result/ ) {
			$command_type = "misc";
		} else {
			$command_type = "check";
		}
		printf ( "CMD;ADD;%s;%s;%s\n", $command->command_name, $command_type, $command->command_line );
		if ( defined ( $command->comment ) ) {
                        printf ( "CMD;setparam;%s;comment;%s\n", $command->command_name, $command->comment );
                }
	}
	
	return 0;
}

# Export Nagios timepriods using Centreon CLAPI format
sub export_timepriods {
	my @timeperiods_array = @_ ;

	foreach my $timeperiod ( @timeperiods_array ) {
		if ( $timeperiod->name =~ m/centreon\-bam|meta\_timeperiod/) {
			next;
		}
		printf ( "TP;ADD;%s;%s\n", $timeperiod->name, $timeperiod->alias );
		printf ( "TP;setparam;%s;tp_sunday;%s\n", $timeperiod->name, $timeperiod->sunday ) if ( defined ($timeperiod->sunday) );
		printf ( "TP;setparam;%s;tp_monday;%s\n", $timeperiod->name, $timeperiod->monday ) if ( defined ($timeperiod->monday) );
		printf ( "TP;setparam;%s;tp_tuesday;%s\n", $timeperiod->name, $timeperiod->tuesday ) if ( defined ($timeperiod->tuesday) );
		printf ( "TP;setparam;%s;tp_wednesday;%s\n", $timeperiod->name, $timeperiod->wednesday ) if ( defined ($timeperiod->wednesday) );
		printf ( "TP;setparam;%s;tp_thursday;%s\n", $timeperiod->name, $timeperiod->thursday ) if ( defined ($timeperiod->thursday) );
		printf ( "TP;setparam;%s;tp_friday;%s\n", $timeperiod->name, $timeperiod->friday ) if ( defined ($timeperiod->friday) );
		printf ( "TP;setparam;%s;tp_saturday;%s\n", $timeperiod->name, $timeperiod->saturday ) if ( defined ($timeperiod->saturday) );
	}
	return 0;
}

# Export Nagios contacts and templates of contact using Centreon CLAPI format
sub export_contacts {
	my @contacts_array = @_ ;

	foreach my $contact ( @contacts_array ) {
		next if ( $contact->contact_name =~ m/centreon\-bam|\_Module\_BAM/ );

		my $contact_name = ( defined ( $contact->contact_name) ? $contact->contact_name : $contact->name );
		my $contact_alias = ( defined ( $contact->alias) ? $contact->alias : $contact->name );
		printf ( "CONTACT;ADD;%s;%s;%s;%s;0;0;en_US;local\n", $contact_alias, $contact_name, $contact->email, $contact->pager );
		printf ( "CONTACT;setparam;%s;hostnotifperiod;%s\n", $contact_name, 
			( defined ${$contact->host_notification_period}{'timeperiod_name'} ? ${$contact->host_notification_period}{'timeperiod_name'} : $contact->host_notification_period() ) );
		printf ( "CONTACT;setparam;%s;svcnotifperiod;%s\n", $contact_name, 
			( defined ${$contact->service_notification_period}{'timeperiod_name'} ? ${$contact->service_notification_period}{'timeperiod_name'} : $contact->service_notification_period() ) );
		printf ( "CONTACT;setparam;%s;hostnotifopt;%s\n", $contact_name, 
			( @{$contact->host_notification_options()} == 0) ? $contact->host_notification_options() : join ( ",", @{$contact->host_notification_options()} ) );
		printf ( "CONTACT;setparam;%s;servicenotifopt;%s\n", $contact_name, 
			( @{$contact->service_notification_options()} == 0) ? $contact->service_notification_options() : join ( ",", @{$contact->service_notification_options()} ) );
		if ( $contact->host_notifications_enabled == 1 || $contact->service_notifications_enabled == 1 ) {
			printf ( "CONTACT;setparam;%s;contact_enable_notifications;1\n", $contact_name );
		} else {
			printf ( "CONTACT;setparam;%s;contact_enable_notifications;0\n", $contact_name );
		}
		printf ( "CONTACT;setparam;%s;contact_activate;0\n", $contact_name);
		
		# Get list of commands
		my $host_commands_list;
		if ( @{$contact->host_notification_commands()} == 0 ) {
			$host_commands_list = $contact->host_notification_commands();
		} else {
			foreach my $obj_command ( @{$contact->host_notification_commands()} ) {
				if ( $host_commands_list == "") {
					$host_commands_list = $obj_command->command_name;
				 } else {
					$host_commands_list .= "|".$obj_command->command_name;
				}
			}
		}
		my $service_commands_list;
		if ( @{$contact->service_notification_commands()} == 0 ) {
			$service_commands_list = $contact->service_notification_commands();
		} else {
			foreach my $obj_command ( @{$contact->service_notification_commands()} ) {
				if ( $service_commands_list == "") {
					$service_commands_list = $obj_command->command_name;
				 } else {
					$service_commands_list .= "|".$obj_command->command_name;
				}
			}
		}	
		printf ( "CONTACT;setparam;%s;hostnotifcmd;%s\n", $contact_name, $host_commands_list );
		printf ( "CONTACT;setparam;%s;svcnotifcmd;%s\n", $contact_name, $service_commands_list );
		printf ( "CONTACT;setparam;%s;address1;%s\n", $contact_name, $contact->address1 ) if ( defined( $contact->address1 ) );
		printf ( "CONTACT;setparam;%s;address2;%s\n", $contact_name, $contact->address2 ) if ( defined( $contact->address2 ) );
		printf ( "CONTACT;setparam;%s;address3;%s\n", $contact_name, $contact->address3 ) if ( defined( $contact->address3 ) );
		printf ( "CONTACT;setparam;%s;address4;%s\n", $contact_name, $contact->address4 ) if ( defined( $contact->address4 ) );
		printf ( "CONTACT;setparam;%s;address5;%s\n", $contact_name, $contact->address5 ) if ( defined( $contact->address5 ) );
		printf ( "CONTACT;setparam;%s;address6;%s\n", $contact_name, $contact->address6 ) if ( defined( $contact->address6 ) );
		printf ( "CONTACT;setparam;%s;register;%s\n", $contact_name, ( defined ( $contact->register ) ? $contact->register : 0 ) );
		printf ( "CONTACT;setparam;%s;comment;%s\n", $contact_name, $contact->comment ) if ( defined ( $contact->comment) );

		# Add contact to contactgroups
		if ( defined ( $contact->contactgroups ) && defined ( @{$contact->contactgroups} ) ) {
			foreach my $contactgroup ( @{$contact->contactgroups} ) {
				foreach my $contact ( @{$contactgroup->members} ) {
					$contactgroups{$contactgroup->contactgroup_name}{$contact->contact_name} = 1;
				}
			}
		}
	}
	
	return 0;
}

# Export Nagios contactgroups using Centreon CLAPI format
sub export_contactgroups {
	my @contactgroups_array = @_ ;

        foreach my $contactgroup ( @contactgroups_array ) {
		my %contacts_exported;
		if ( $contactgroup->contactgroup_name !~ m/centreon\-bam\-contactgroup|\_Module\_BAM/ ) {
			printf ( "CG;ADD;%s;%s\n", $contactgroup->contactgroup_name, $contactgroup->alias );
			printf ( "CG;setparam;%s;cg_activate;1\n", $contactgroup->contactgroup_name );
			printf ( "CG;setparam;%s;cg_type;local\n", $contactgroup->contactgroup_name );
			# loop to add contacts from contactgroup definition
			if ( defined ( $contactgroup->members ) ) {
				foreach my $contact ( @{$contactgroup->members} ) {
					if ( !defined ( $contacts_exported{$contact->contact_name} ) ) {
						printf ( "CG;addcontact;%s;%s\n", $contactgroup->contactgroup_name, $contact->contact_name );
						$contacts_exported{$contact->contact_name} = 1;
					}
				}
			}
			# loop to add contacts from contact definition
			if ( defined ( $contactgroups{$contactgroup->contactgroup_name} ) ) {
				foreach my $contacts ( $contactgroups{$contactgroup->contactgroup_name} ) {
					foreach my $contact ( keys %{$contacts} ) {
						if ( !defined ( $contacts_exported{$contact} ) ) {
							printf ( "CG;addcontact;%s;%s\n", $contactgroup->contactgroup_name, $contact );
						}
					}
				}
			}
		}
	}
}

# Export Nagios hosts and templates of hosts using Centreon CLAPI format
sub export_hosts {
	my @hosts_array = @_;
	foreach my $host ( @hosts_array ) {
		if ( defined ( $host->use ) ) {
			my @tpls_used = split ( ',', $host->use );
			foreach my $tpl (@tpls_used) {
				if ( !defined ( $hostTemplates_exported{$tpl} ) ) {
					export_hosts ( $objects->find_object( $tpl, "Nagios::Host" ) ) ;
				} else {
					next;
				}
			}
		}

		if ( ( $host->name !~ m/\_Module\_BAM/ ) && ( $hostTemplates_exported{$host->name} == 0) ) {
			my $type = "HOST";
			my $host_name;
			my $list_of_tpl = $host->use if ( defined ( $host->use ) );
			$list_of_tpl =~ s/,/|/ if ( defined ( $host->use ) );;
			#my $list_of_hostgroup = $host->use if ( defined ( $host->hostgroups ) );
			#$list_of_hostgroup =~ s/,/|/ if ( defined ( $host->hostgroups ) );;
			
			if ( !defined ( $host->register ) || $host->register == 0 || !defined ( $host->address )  ) {
				printf ( "HTPL;ADD;%s;%s;%s;%s;;\n", $host->name, ( defined ( $host->alias ) ? $host->alias : $host->name ), $host->address, $list_of_tpl ) ;
				$type = "HTPL";
				$host_name = $host->name;
			} else {
				printf ( "HOST;ADD;%s;%s;%s;%s;%s;\n", $host->host_name, ( defined ( $host->alias ) ? $host->alias : $host->name ), $host->address, $list_of_tpl, $default_poller );
				$type = "HOST";
				$host_name = $host->host_name;
			}
			printf ( "%s;setparam;%s;2d_coords;%s\n", $type, $host_name, $host->{'2d_coords'} ) if ( defined ( $host->{'2d_coords'} ) );
			printf ( "%s;setparam;%s;3d_coords;%s\n", $type, $host_name, $host->{'3d_coords'} ) if ( defined ( $host->{'3d_coords'} ) );
			printf ( "%s;setparam;%s;action_url;%s\n", $type, $host_name, $host->action_url ) if ( defined ( $host->action_url ) );
			printf ( "%s;setparam;%s;active_checks_enabled;%s\n", $type, $host_name, $host->active_checks_enabled ) if ( defined ( $host->active_checks_enabled ) );
			my ($check_command, $check_command_arguments);
			if ( defined ( $host->check_command ) ) {
				$check_command = $host->check_command ;
				($check_command, $check_command_arguments) = split ( '!', $check_command, 2 ) ;
				printf ( "%s;setparam;%s;check_command;%s\n", $type, $host_name, $check_command )  if ( $check_command !~ m/^\$/ );
				printf ( "%s;setparam;%s;check_command_arguments;!%s\n", $type, $host_name, $check_command_arguments )  if ( defined ( $check_command_arguments ) );
			}
			printf ( "%s;setparam;%s;check_interval;%s\n", $type, $host_name, $host->check_interval ) if ( defined ( $host->check_interval ) );
			printf ( "%s;setparam;%s;check_freshness;%s\n", $type, $host_name, $host->check_freshness ) if ( defined ( $host->check_freshness ) );
			printf ( "%s;setparam;%s;freshness_threshold;%s\n", $type, $host_name, $host->freshness_threshold ) if ( defined ( $host->freshness_threshold ) );
			printf ( "%s;setparam;%s;check_period;%s\n", $type, $host_name, 
				( defined ${$host->check_period}{'timeperiod_name'} ? ${$host->check_period}{'timeperiod_name'} : $host->check_period ) ) if ( defined ( $host->check_period ) );
			printf ( "%s;setparam;%s;initial_state;%s\n", $type, $host_name, 
				( @{$host->initial_state()} == 0 ) ? $host->initial_state() : join ( ",", @{$host->initial_state} ) ) if ( defined ( $host->initial_state ) );
			printf ( "%s;setparam;%s;event_handler;%s\n", $type, $host_name, $host->event_handler ) if ( defined ( $host->event_handler ) );
			printf ( "%s;setparam;%s;event_handler_enabled;%s\n", $type, $host_name, $host->event_handler_enabled ) if ( defined ( $host->event_handler_enabled ) );
			printf ( "%s;setparam;%s;failure_prediction_enabled;%s\n", $type, $host_name, $host->failure_prediction_enabled ) if ( defined ( $host->failure_prediction_enabled ) );
			printf ( "%s;setparam;%s;first_notification_delay;%s\n", $type, $host_name, $host->first_notification_delay ) if ( defined ( $host->first_notification_delay ) );
			printf ( "%s;setparam;%s;flap_detection_enabled;%s\n", $type, $host_name, $host->flap_detection_enabled ) if ( defined ( $host->flap_detection_enabled ) );
			printf ( "%s;setparam;%s;flap_detection_options;%s\n", $type, $host_name, 
				( @{$host->flap_detection_options()} == 0) ? $host->flap_detection_options() : join ( ",", @{$host->flap_detection_options} ) ) if ( defined ( $host->flap_detection_options ) );
			printf ( "%s;setparam;%s;low_flap_threshold;%s\n", $type, $host_name, $host->low_flap_threshold ) if ( defined ( $host->low_flap_threshold ) );
			printf ( "%s;setparam;%s;high_flap_threshold;%s\n", $type, $host_name, $host->high_flap_threshold ) if ( defined ( $host->high_flap_threshold ) );
			printf ( "%s;setparam;%s;max_check_attempts;%s\n", $type, $host_name, $host->max_check_attempts ) if ( defined ( $host->max_check_attempts ) );
			#printf ( "%s;setparam;%s;normal_check_interval;%s\n", $type, $host_name, $host->check_interval ) if ( defined ( $host->check_interval ) );
			printf ( "%s;setparam;%s;notes;%s\n", $type, $host_name, $host->notes ) if ( defined ( $host->notes ) );
			printf ( "%s;setparam;%s;notes_url;%s\n", $type, $host_name, $host->notes_url ) if ( defined ( $host->notes_url ) );
			printf ( "%s;setparam;%s;notifications_enabled;%s\n", $type, $host_name, $host->notifications_enabled ) if ( defined ( $host->notifications_enabled ) );
			printf ( "%s;setparam;%s;notification_interval;%s\n", $type, $host_name, $host->notification_interval ) if ( defined ( $host->notification_interval ) );
			printf ( "%s;setparam;%s;notification_options;%s\n", $type, $host_name, 
				( @{$host->notification_options()} == 0) ? $host->notification_options() : join ( ",", @{$host->notification_options} ) ) if ( defined ( $host->notification_options ) );
			printf ( "%s;setparam;%s;notification_period;%s\n", $type, $host_name, 
				( defined ${$host->notification_period}{'timeperiod_name'} ? ${$host->notification_period}{'timeperiod_name'} : $host->notification_period ) ) if ( defined ( $host->notification_period ) );
			printf ( "%s;setparam;%s;obsess_over_host;%s\n", $type, $host_name, $host->obsess_over_host ) if ( defined ( $host->obsess_over_host ) );
			# Define parental dependencies
			if ( defined ( $host->parents ) ) {
				my $parents;
				foreach my $host ( @{$host->parents} ) {
					if ( $parents == "" ) {
						$parents = $host_name;
					} else {
						$parents .= "|".$host_name;
					}
				}
				printf ( "%s;setparam;%s;parents;%s\n", $type, $host_name, $parents );
			}
			printf ( "%s;setparam;%s;passive_checks_enabled;%s\n", $type, $host_name, $host->passive_checks_enabled ) if ( defined ( $host->passive_checks_enabled ) );
			printf ( "%s;setparam;%s;process_perf_data;%s\n", $type, $host_name, $host->process_perf_data ) if ( defined ( $host->process_perf_data ) );
			printf ( "%s;setparam;%s;retain_nonstatus_information;%s\n", $type, $host_name, $host->retain_nonstatus_information ) if ( defined ( $host->retain_nonstatus_information ) );
			printf ( "%s;setparam;%s;retain_status_information;%s\n", $type, $host_name, $host->retain_status_information ) if ( defined ( $host->retain_status_information ) );
			printf ( "%s;setparam;%s;retry_check_interval;%s\n", $type, $host_name, $host->retry_interval ) if ( defined ( $host->retry_interval ) );
			printf ( "%s;setparam;%s;stalking_options;%s\n", $type, $host_name, 
				( @{$host->stalking_options()} == 0) ? $host->stalking_options() : join ( ",", @{$host->stalking_options} ) ) if ( defined ( $host->stalking_options ) );

			# Add contactgroups to host
			if ( defined ( $host->contact_groups )  && $host->contact_groups != "" ) {
				my $contactgroups;
				foreach my $contactgroup ( @{$host->contact_groups} ) {
					if ( $contactgroups == "" ) {
						$contactgroups = $contactgroup->contactgroup_name;
					} else {
						$contactgroups .= "|".$contactgroup->contactgroup_name;
					}
				}
				printf ( "%s;addcontactgroup;%s;%s\n", $type, $host_name, $contactgroups );
			}

			# Add contacts to host
			if ( defined ( $host->contacts ) && $host->contacts != "" ) {
				my $contacts;
				foreach my $contact ( @{$host->contacts} ) {
					if ( $contacts == "" ) {
						$contacts = $contact->name;
					} else {
						$contacts .= "|".$contact->name;
					}
				}
				printf ( "%s;setcontact;%s;%s\n", $type, $host_name, $contacts );
			}

			# Add host to hostgroups
			if (defined ( $host->hostgroups ) ) {
				foreach my $hostgroup ( @{$host->hostgroups} ) {
					foreach my $host ( @{$hostgroup->members} ) {
						$hostgroups{$hostgroup->hostgroup_name}{$host_name} = 1;
					}
				}
			}
		
			# Export host Extended info
			my $hostextendedinfo = $objects->find_object( $host_name, "Nagios::HostExtInfo" );
			if ( defined ( $hostextendedinfo ) && $hostextendedinfo != 0 ) {
				printf ( "%s;setparam;%s;notes;%s\n", $type, $host_name, $hostextendedinfo->notes ) if ( defined ( $hostextendedinfo->notes ) );
				printf ( "%s;setparam;%s;notes_url;%s\n", $type, $host_name, $hostextendedinfo->notes_url ) if ( defined ( $hostextendedinfo->notes_url ) );
				printf ( "%s;setparam;%s;action_url;%s\n", $type, $host_name, $hostextendedinfo->action_url ) if ( defined ( $hostextendedinfo->action_url ) );
				printf ( "%s;setparam;%s;icon_image;%s\n", $type, $host_name, $hostextendedinfo->icon_image ) if ( defined ( $hostextendedinfo->icon_image ) );
				printf ( "%s;setparam;%s;icon_image_alt;%s\n", $type, $host_name, $hostextendedinfo->icon_image_alt ) if ( defined ( $hostextendedinfo->icon_image_alt ) );
				printf ( "%s;setparam;%s;vrml_image;%s\n", $type, $host_name, $hostextendedinfo->vrml_image ) if ( defined ( $hostextendedinfo->vrml_image ) );
				printf ( "%s;setparam;%s;statusmap_image;%s\n", $type, $host_name, $hostextendedinfo->statusmap_image ) if ( defined ( $hostextendedinfo->statusmap_image ) );
				printf ( "%s;setparam;%s;2d_coords;%s\n", $type, $host_name, $hostextendedinfo->{'2d_coords'} ) if ( defined ( $hostextendedinfo->{'2d_coords'} ) );
				printf ( "%s;setparam;%s;3d_coords;%s\n", $type, $host_name, $hostextendedinfo->{'3d_coords'} ) if ( defined ( $hostextendedinfo->{'3d_coords'} ) );
			}
			# To do not export twice template
			$hostTemplates_exported{$host->name} = 1;
		}
	}
}

# Export Nagios hostgroups using Centreon CLAPI format
sub export_hostgroups {
	my @hostgroups_array = @_ ;

	foreach my $hostgroup ( @hostgroups_array ) {
		my %hosts_exported;
		if ( $hostgroup->hostgroup_name !~ m/centreon\-bam\-contactgroup|\_Module\_BAM/ ) {
			printf ( "HG;ADD;%s;%s\n", $hostgroup->hostgroup_name, $hostgroup->alias );
			printf ( "HG;setparam;%s;hg_activate;1\n", $hostgroup->hostgroup_name );
			# loop to add hosts from hostgroups definition
			if ( defined ( $hostgroup->members ) ) {
				foreach my $host ( @{$hostgroup->members} ) {
					if ( !defined ( $hosts_exported{$host->host_name} ) ) {
						printf ( "HG;addhost;%s;%s\n", $hostgroup->hostgroup_name, $host->host_name );
						$hosts_exported{$host->host_name} = 1;
					}
				}
			}
			# loop to add hosts from host definition
			if ( defined ( $hostgroups{$hostgroup->hostgroup_name} ) ) {
				foreach my $hosts ( $hostgroups{$hostgroup->hostgroup_name} ) {
					foreach my $host ( keys %{$hosts} ) {
						if ( !defined ( $hosts_exported{$host} ) ) {
							printf ( "HG;addhost;%s;%s\n", $hostgroup->hostgroup_name, $host );
						}
					}
				}
			}
		}
	}
}

# Export Nagios host dependency using Centreon CLAPI format
sub export_hostdependencies {
	my @hostdependencies_array = @_ ;

	foreach my $hostdependencie ( @hostdependencies_array ) {
		my ($dependent_host_name, $dependent_hostgroup_name, $host_name, $hostgroup_name, $element);
		
		# Hostgroup dependancy
		if ( ( @{$hostdependencie->dependent_hostgroup_name} != 0 ) && ( @{$hostdependencie->hostgroup_name} != 0 ) ) {
			foreach $element ( @{$hostdependencie->hostgroup_name} ) {
				if ( $hostgroup_name == "" ) {
					$hostgroup_name = $element->hostgroup_name;
				} else {
					$hostgroup_name .= "|".$element->hostgroup_name;
				}
			}
		
			printf ( "DEP;ADD;%s;%s;HG;%s\n", $hostdependencie->name, $hostdependencie->name, $hostgroup_name );
			
			foreach $element ( @{$hostdependencie->dependent_hostgroup_name} ) {
				printf ( "DEP;ADDPARENT;%s;%s\n", $hostdependencie->name, $element->hostgroup_name);
			}
		}
		# Host dependancy
		if ( ( @{$hostdependencie->dependent_host_name} != 0 ) && ( @{$hostdependencie->host_name} != 0 ) ) {
			foreach $element ( @{$hostdependencie->host_name} ) {
				if ( $host_name == "" ) {
					$host_name = $element->name;
				} else {
					$host_name .= "|".$element->name;
				}
			}
		
			printf ( "DEP;ADD;%s;%s;HOST;%s\n", $hostdependencie->name, $hostdependencie->name, $host_name );
			
			foreach $element ( @{$hostdependencie->dependent_host_name} ) {
				printf ( "DEP;ADDPARENT;%s;%s\n", $hostdependencie->name, $element->name);
			}
		}
	}
}

# Export Nagios services and templates of services using Centreon CLAPI format
sub export_services {
	my @services_array = @_;
	foreach my $service ( @services_array ) {
		if ( defined ( $service->use ) ) {
			export_services ( $objects->find_object( $service->use, "Nagios::Service" ) ) ;
		}
		my $host_name;
				
		if ( ( $service->name !~ m/ba\_/ ) && ( $serviceTemplates_exported{$service->name} == 0 ) ) {
			my $service_name;
			my $type = "SERVICE";
			if ( defined ( $service->hostgroup_name ) ) {
				# Create template of service
				$type = "STPL";
				$service_name = "from_service_by_hg_".$service->name;
				printf ( "%s;ADD;%s;%s;%s\n", $type, $service_name, ( defined ( $service->service_description ) ? $service->service_description : $service_name ), $service->use );
				printf ( "%s;setparam;%s;is_volatile;%s\n", $type, $service_name, $service->is_volatile ) if ( defined ( $service->is_volatile ) );
				printf ( "%s;setparam;%s;check_period;%s\n", $type, $service_name, 
					( defined ${$service->check_period}{'timeperiod_name'} ? ${$service->check_period}{'timeperiod_name'} : $service->check_period ) ) if ( defined ( $service->check_period ) );
				my ($check_command, $check_command_arguments);
				if ( defined ( $service->check_command ) ) {
					$check_command = ( defined ( ${$service->check_command}{'command_name'} ) ? ${$service->check_command}{'command_name'} : $service->check_command );
					($check_command, $check_command_arguments) = split ( '!', $check_command, 2 ) ;
					printf ( "%s;setparam;%s;check_command;%s\n", $type, $service_name, $check_command )  if ( $check_command !~ m/^\$/ );
					printf ( "%s;setparam;%s;check_command_arguments;!%s\n", $type, $service_name, $check_command_arguments )  if ( defined ( $check_command_arguments ) );
				}
				# Not available in Centreon CLAPI v1.8
				#printf ( "%s;setparam;%s;initial_state;%s\n", $type, $service_name, 
				#	( @{$service->initial_state()} == 0 ) ? $service->initial_state() : join ( ",", @{$service->initial_state} ) ) if ( defined ( $service->initial_state ) );
				printf ( "%s;setparam;%s;max_check_attempts;%s\n", $type, $service_name, $service->max_check_attempts ) if ( defined ( $service->max_check_attempts ) );
				printf ( "%s;setparam;%s;normal_check_interval;%s\n", $type, $service_name, $service->check_interval ) if ( defined ( $service->check_interval ) );
				printf ( "%s;setparam;%s;retry_check_interval;%s\n", $type, $service_name, $service->retry_interval ) if ( defined ( $service->retry_interval ) );
				printf ( "%s;setparam;%s;active_checks_enabled;%s\n", $type, $service_name, $service->active_checks_enabled ) if ( defined ( $service->active_checks_enabled ) );
				printf ( "%s;setparam;%s;passive_checks_enabled;%s\n", $type, $service_name, $service->passive_checks_enabled ) if ( defined ( $service->passive_checks_enabled ) );
				printf ( "%s;setparam;%s;notifications_enabled;%s\n", $type, $service_name, $service->notifications_enabled ) if ( defined ( $service->notifications_enabled ) );
				printf ( "%s;setparam;%s;notification_interval;%s\n", $type, $service_name, $service->notification_interval ) if ( defined ( $service->notification_interval ) );
				printf ( "%s;setparam;%s;notification_period;%s\n", $type, $service_name, 
					( defined ${$service->notification_period}{'timeperiod_name'} ? ${$service->notification_period}{'timeperiod_name'} : $service->notification_period ) ) if ( defined ( $service->notification_period ) );
				printf ( "%s;setparam;%s;notification_options;%s\n", $type, $service_name, 
					( @{$service->notification_options()} == 0 ) ? $service->notification_options() : join ( ",", @{$service->notification_options} ) ) if ( defined ( $service->notification_options ) );
				printf ( "%s;setparam;%s;first_notification_delay;%s\n", $type, $service_name, $service->first_notification_delay ) if ( defined ( $service->first_notification_delay ) ); 
				printf ( "%s;setparam;%s;parallelize_check;%s\n", $type, $service_name, $service->parallelize_check ) if ( defined ( $service->parallelize_check ) ); 
				printf ( "%s;setparam;%s;obsess_over_service;%s\n", $type, $service_name, $service->obsess_over_service ) if ( defined ( $service->obsess_over_service ) ); 
				printf ( "%s;setparam;%s;check_freshness;%s\n", $type, $service_name, $service->check_freshness ) if ( defined ( $service->check_freshness ) ); 
				printf ( "%s;setparam;%s;freshness_threshold;%s\n", $type, $service_name, $service->freshness_threshold ) if ( defined ( $service->freshness_threshold ) ); 
				printf ( "%s;setparam;%s;flap_detection_enabled;%s\n", $type, $service_name, $service->flap_detection_enabled ) if ( defined ( $service->flap_detection_enabled ) ); 
				printf ( "%s;setparam;%s;flap_detection_options;%s\n", $type, $service_name, 
					( @{$service->flap_detection_options()} == 0) ? $service->flap_detection_options() : join ( ",", @{$service->flap_detection_options} ) ) if ( defined ( $service->flap_detection_options ) );
				printf ( "%s;setparam;%s;low_flap_threshold;%s\n", $type, $service_name, $service->low_flap_threshold ) if ( defined ( $service->low_flap_threshold ) ); 
				printf ( "%s;setparam;%s;high_flap_threshold;%s\n", $type, $service_name, $service->high_flap_threshold ) if ( defined ( $service->high_flap_threshold ) ); 
				printf ( "%s;setparam;%s;process_perf_data;%s\n", $type, $service_name, $service->process_perf_data ) if ( defined ( $service->process_perf_data ) ); 
				printf ( "%s;setparam;%s;retain_status_information;%s\n", $type, $service_name, $service->retain_status_information ) if ( defined ( $service->retain_status_information ) ); 
				printf ( "%s;setparam;%s;retain_nonstatus_information;%s\n", $type, $service_name, $service->retain_nonstatus_information ) if ( defined ( $service->retain_nonstatus_information ) ); 
				printf ( "%s;setparam;%s;stalking_options;%s\n", $type, $service_name, 
					( @{$service->stalking_options()} == 0) ? $service->stalking_options() : join ( ",", @{$service->stalking_options} ) ) if ( defined ( $service->stalking_options ) );
				printf ( "%s;setparam;%s;failure_prediction_enabled;%s\n", $type,$service_name, $service->failure_prediction_enabled ) if ( defined ( $service->failure_prediction_enabled ) );
				printf ( "%s;setparam;%s;event_handler;%s\n", $type, $service_name, $service->event_handler ) if ( defined ( $service->event_handler ) ); 
				printf ( "%s;setparam;%s;event_handler_enabled;%s\n", $type, $service_name, $service->event_handler_enabled ) if ( defined ( $service->event_handler_enabled ) ); 
				printf ( "%s;setparam;%s;notes;%s\n", $type, $service_name, $service->notes ) if ( defined ( $service->notes ) ); 	
				printf ( "%s;setparam;%s;notes_url;%s\n", $type, $service_name, $service->notes_url ) if ( defined ( $service->notes_url ) ); 	
				printf ( "%s;setparam;%s;action_url;%s\n", $type, $service_name, $service->action_url ) if ( defined ( $service->action_url ) ); 	
				printf ( "%s;setparam;%s;comment;%s\n", $type, $service_name, $service->comment ) if ( defined ( $service->comment ) ); 

				# Add contactgroups to service
				if ( defined ( $service->contact_groups )  && $service->contact_groups != "" ) {
					my $contactgroups;
					foreach my $contactgroup ( @{$service->contact_groups} ) {
						if ( $contactgroups == "" ) {
							$contactgroups = $contactgroup->contactgroup_name;
						} else {
							$contactgroups .= "|".$contactgroup->contactgroup_name;
						}
					}
					printf ( "%s;addcontactgroup;%s%s;%s\n", $type, $host_name, $service_name, $contactgroups );
				}

				# Add contacts to service
				if ( defined ( $service->contacts ) && $service->contacts != "" ) {
					my $contacts;
					foreach my $contact ( @{$service->contacts} ) {
						if ( $contacts == "" ) {
							$contacts = $contact->name;
						} else {
							$contacts .= "|".$contact->name;
						}
					}
					printf ( "%s;addcontact;%s%s;%s\n", $type, $host_name, $service_name, $contacts );
				}
				
				# Deploy service based on previous template on all host linked to hostgroup
				foreach my $hostgroup ( @{$service->hostgroup_name} ) {
						foreach my $host ( @{$hostgroup->members} ) {
							printf ( "SERVICE;ADD;%s;%s;%s\n", $host->host_name, $service->name, $service_name );
						}
				}
			} else {
				if ( !defined ( $service->register ) || $service->register == 0 ) {
					$type = "STPL";
					$service_name = $service->name;
					printf ( "STPL;ADD;%s;%s;%s\n", $service_name, ( defined ( $service->service_description ) ? $service->service_description : $service_name ), $service->use );
				} else {
					$type = "SERVICE";
					$service_name = $service->name;
					foreach $host ( @{$service->host_name} ) {
						$host_name = $host->host_name;
					}
					$host_name .= ";";
					printf ( "%s;ADD;%s%s;%s\n", $type, $host_name, $service_name, $service->use );
					#printf ( "%s;setparam;%s%s;template;%s\n", $type, $host_name, $service_name, $service->use ) if ( defined ( $service->use ) );
					printf ( "%s;setparam;%s%s;description;%s\n", $type, $host_name, $service_name, $service->service_description ) if ( defined ( $service->service_description ) );
				}
				printf ( "%s;setparam;%s%s;is_volatile;%s\n", $type, $host_name, $service_name, $service->is_volatile ) if ( defined ( $service->is_volatile ) );
				printf ( "%s;setparam;%s%s;check_period;%s\n", $type, $host_name, $service_name, 
					( defined ${$service->check_period}{'timeperiod_name'} ? ${$service->check_period}{'timeperiod_name'} : $service->check_period ) ) if ( defined ( $service->check_period ) );
				my ($check_command, $check_command_arguments);
				if ( defined ( $service->check_command ) ) {
					$check_command = ( defined ( ${$service->check_command}{'command_name'} ) ? ${$service->check_command}{'command_name'} : $service->check_command );
					($check_command, $check_command_arguments) = split ( '!', $check_command, 2 ) ;
					printf ( "%s;setparam;%s%s;check_command;%s\n", $type, $host_name, $service_name, $check_command )  if ( $check_command !~ m/^\$/ );
					printf ( "%s;setparam;%s%s;check_command_arguments;!%s\n", $type, $host_name, $service_name, $check_command_arguments )  if ( defined ( $check_command_arguments ) );
				}
				# Not available in Centreon CLAPI v1.8
				#printf ( "%s;setparam;%s%s;initial_state;%s\n", $type, $host_name, $service_name, 
				#	( @{$service->initial_state()} == 0 ) ? $service->initial_state() : join ( ",", @{$service->initial_state} ) ) if ( defined ( $service->initial_state ) );
				printf ( "%s;setparam;%s%s;max_check_attempts;%s\n", $type, $host_name, $service_name, $service->max_check_attempts ) if ( defined ( $service->max_check_attempts ) );
				printf ( "%s;setparam;%s%s;normal_check_interval;%s\n", $type, $host_name, $service_name, $service->check_interval ) if ( defined ( $service->check_interval ) );
				printf ( "%s;setparam;%s%s;retry_check_interval;%s\n", $type, $host_name, $service_name, $service->retry_interval ) if ( defined ( $service->retry_interval ) );
				printf ( "%s;setparam;%s%s;active_checks_enabled;%s\n", $type, $host_name, $service_name, $service->active_checks_enabled ) if ( defined ( $service->active_checks_enabled ) );
				printf ( "%s;setparam;%s%s;passive_checks_enabled;%s\n", $type, $host_name, $service_name, $service->passive_checks_enabled ) if ( defined ( $service->passive_checks_enabled ) );
				printf ( "%s;setparam;%s%s;notifications_enabled;%s\n", $type, $host_name, $service_name, $service->notifications_enabled ) if ( defined ( $service->notifications_enabled ) );
				printf ( "%s;setparam;%s%s;notification_interval;%s\n", $type, $host_name, $service_name, $service->notification_interval ) if ( defined ( $service->notification_interval ) );
				printf ( "%s;setparam;%s%s;notification_period;%s\n", $type, $host_name, $service_name, 
					( defined ${$service->notification_period}{'timeperiod_name'} ? ${$service->notification_period}{'timeperiod_name'} : $service->notification_period ) ) if ( defined ( $service->notification_period ) );
				printf ( "%s;setparam;%s%s;notification_options;%s\n", $type, $host_name, $service_name, 
					( @{$service->notification_options()} == 0 ) ? $service->notification_options() : join ( ",", @{$service->notification_options} ) ) if ( defined ( $service->notification_options ) );
				printf ( "%s;setparam;%s%s;first_notification_delay;%s\n", $type, $host_name, $service_name, $service->first_notification_delay ) if ( defined ( $service->first_notification_delay ) ); 
				printf ( "%s;setparam;%s%s;parallelize_check;%s\n", $type, $host_name, $service_name, $service->parallelize_check ) if ( defined ( $service->parallelize_check ) ); 
				printf ( "%s;setparam;%s%s;obsess_over_service;%s\n", $type, $host_name, $service_name, $service->obsess_over_service ) if ( defined ( $service->obsess_over_service ) ); 
				printf ( "%s;setparam;%s%s;check_freshness;%s\n", $type, $host_name, $service_name, $service->check_freshness ) if ( defined ( $service->check_freshness ) ); 
				printf ( "%s;setparam;%s%s;freshness_threshold;%s\n", $type, $host_name, $service_name, $service->freshness_threshold ) if ( defined ( $service->freshness_threshold ) ); 
				printf ( "%s;setparam;%s%s;flap_detection_enabled;%s\n", $type, $host_name, $service_name, $service->flap_detection_enabled ) if ( defined ( $service->flap_detection_enabled ) ); 
				printf ( "%s;setparam;%s%s;flap_detection_options;%s\n", $type, $host_name, $service_name, 
					( @{$service->flap_detection_options()} == 0) ? $service->flap_detection_options() : join ( ",", @{$service->flap_detection_options} ) ) if ( defined ( $service->flap_detection_options ) );
				printf ( "%s;setparam;%s%s;low_flap_threshold;%s\n", $type, $host_name, $service_name, $service->low_flap_threshold ) if ( defined ( $service->low_flap_threshold ) ); 
				printf ( "%s;setparam;%s%s;high_flap_threshold;%s\n", $type, $host_name, $service_name, $service->high_flap_threshold ) if ( defined ( $service->high_flap_threshold ) ); 
				printf ( "%s;setparam;%s%s;process_perf_data;%s\n", $type, $host_name, $service_name, $service->process_perf_data ) if ( defined ( $service->process_perf_data ) ); 
				printf ( "%s;setparam;%s%s;retain_status_information;%s\n", $type, $host_name, $service_name, $service->retain_status_information ) if ( defined ( $service->retain_status_information ) ); 
				printf ( "%s;setparam;%s%s;retain_nonstatus_information;%s\n", $type, $host_name, $service_name, $service->retain_nonstatus_information ) if ( defined ( $service->retain_nonstatus_information ) ); 
				printf ( "%s;setparam;%s%s;stalking_options;%s\n", $type, $host_name, $service_name, 
					( @{$service->stalking_options()} == 0) ? $service->stalking_options() : join ( ",", @{$service->stalking_options} ) ) if ( defined ( $service->stalking_options ) );
				printf ( "%s;setparam;%s%s;failure_prediction_enabled;%s\n", $type, $host_name, $service_name, $service->failure_prediction_enabled ) if ( defined ( $service->failure_prediction_enabled ) );
				printf ( "%s;setparam;%s%s;event_handler;%s\n", $type, $host_name, $service_name, $service->event_handler ) if ( defined ( $service->event_handler ) ); 
				printf ( "%s;setparam;%s%s;event_handler_enabled;%s\n", $type, $host_name, $service_name, $service->event_handler_enabled ) if ( defined ( $service->event_handler_enabled ) ); 
				printf ( "%s;setparam;%s%s;notes;%s\n", $type, $host_name, $service_name, $service->notes ) if ( defined ( $service->notes ) ); 	
				printf ( "%s;setparam;%s%s;notes_url;%s\n", $type, $host_name, $service_name, $service->notes_url ) if ( defined ( $service->notes_url ) ); 	
				printf ( "%s;setparam;%s%s;action_url;%s\n", $type, $host_name, $service_name, $service->action_url ) if ( defined ( $service->action_url ) ); 	
				printf ( "%s;setparam;%s%s;comment;%s\n", $type, $host_name, $service_name, $service->comment ) if ( defined ( $service->comment ) ); 

				# Add contactgroups to service
				if ( defined ( $service->contact_groups )  && $service->contact_groups != "" ) {
					my $contactgroups;
					foreach my $contactgroup ( @{$service->contact_groups} ) {
						if ( $contactgroups == "" ) {
							$contactgroups = $contactgroup->contactgroup_name;
						} else {
							$contactgroups .= "|".$contactgroup->contactgroup_name;
						}
					}
					printf ( "%s;addcontactgroup;%s%s;%s\n", $type, $host_name, $service_name, $contactgroups );
				}

				# Add contacts to service
				if ( defined ( $service->contacts ) && $service->contacts != "" ) {
					my $contacts;
					foreach my $contact ( @{$service->contacts} ) {
						if ( $contacts == "" ) {
							$contacts = $contact->name;
						} else {
							$contacts .= "|".$contact->name;
						}
					}
					printf ( "%s;addcontact;%s%s;%s\n", $type, $host_name, $service_name, $contacts );
				}

				# Add service to servicegroups
				if (defined ( $service->servicegroups ) ) {
					foreach my $servicegroup ( @{$service->servicegroups} ) {
						foreach my $service ( @{$servicegroup->members} ) {
							$servicegroups{$servicegroup->servicegroup_name}{$service->name} = $service->host_name;
						}
					}
				}
			}
		}
		$serviceTemplates_exported{$service->name} = 1;
	}
}

# Export Nagios serviceextinfo using Centreon CLAPI format
sub export_serviceextinfo {
	my @list_serviceextendedinfo = @_ ;
	
	foreach my $serviceextendedinfo ( @list_serviceextendedinfo ) {
		my ($host_name, $type);
		foreach my $host ( @{$serviceextendedinfo->host_name} ) {
			$host_name = $host->host_name;
		}
		if ( defined ( $serviceextendedinfo ) && ( $serviceextendedinfo != 0 ) && defined ( $host_name ) ) {
			if ( !defined ( ${$serviceextendedinfo->service_description}{'register'} ) || ${$serviceextendedinfo->service_description}{'register'} == 0 ) {
				$type = "STPL";
			} else {
				$type = "SERVICE";
			}
			printf ( "%s;setparam;%s%s;notes;%s\n", $type, $host_name, ${$serviceextendedinfo->service_description}{'service_description'}, $serviceextendedinfo->notes ) if ( defined ( $serviceextendedinfo->notes ) );
			printf ( "%s;setparam;%s%s;notes_url;%s\n", $type, $host_name, ${$serviceextendedinfo->service_description}{'service_description'}, $serviceextendedinfo->notes_url ) if ( defined ( $serviceextendedinfo->notes_url ) );
			printf ( "%s;setparam;%s%s;action_url;%s\n", $type, $host_name, ${$serviceextendedinfo->service_description}{'service_description'}, $serviceextendedinfo->action_url ) if ( defined ( $serviceextendedinfo->action_url ) );
			printf ( "%s;setparam;%s%s;icon_image;%s\n", $type, $host_name, ${$serviceextendedinfo->service_description}{'service_description'}, $serviceextendedinfo->icon_image ) if ( defined ( $serviceextendedinfo->icon_image ) );
			printf ( "%s;setparam;%s%s;icon_image_alt;%s\n", $type, $host_name, ${$serviceextendedinfo->service_description}{'service_description'}, $serviceextendedinfo->icon_image_alt ) if ( defined ( $serviceextendedinfo->icon_image_alt ) );
		}
	}
}

# Export Nagios hostservicegroups using Centreon CLAPI format
sub export_servicegroups {
	my @servicegroups_array = @_ ;

	foreach my $servicegroup ( @servicegroups_array ) {
		my %services_exported;
		if ( $servicegroup->servicegroup_name !~ m/centreon\-bam\-contactgroup|\_Module\_BAM/ ) {
			printf ( "SG;ADD;%s;%s\n", $servicegroup->servicegroup_name, $servicegroup->alias );
			printf ( "SG;setparam;%s;sg_activate;1\n", $servicegroup->servicegroup_name );
			# loop to add services from servicegroups definition
			if ( defined ( $servicegroup->members ) ) {
				foreach my $service ( @{$servicegroup->members} ) {
					if ( !defined ( $services_exported{$service->service_name} ) ) {
						printf ( "HG;addservice;%s,%s\n", $servicegroup->servicegroup_name, $service->host_name, $service->service_name );
						$services_exported{$service->service_name} = $service->host_name;
					}
				}
			}
			# loop to add services from service definition
			if ( defined ( $servicegroups{$servicegroup->servicegroup_name} ) ) {
				foreach my $services ( $servicegroups{$servicegroup->servicegroup_name} ) {
					foreach my $service ( keys %{$services} ) {
						if ( !defined ( $services_exported{$service} ) ) {
							printf ( "SG;addservice;%s,%s\n", $servicegroup->servicegroup_name, $services_exported{$service}, $service );
						}
					}
				}
			}
		}
	}
}

# Load Nagios configuration from main.cfg file
$objects = Nagios::Config->new( Filename => $OPTION{'config'}, force_relative_files => 0 );

# Generate Centreon CLAPI commands
export_clapi_commands ( $objects->list_commands() );
export_timepriods ( $objects->list_timeperiods() );
export_contacts ( $objects->list_contacts() );
export_contactgroups ( $objects->list_contactgroups() );
export_hosts ( $objects->list_hosts() );
export_hostgroups ( $objects->list_hostgroups() );
export_hostdependencies ( $objects->list_hostdependencies );
export_services ( $objects->list_services() );
export_serviceextinfo ( $objects->list_serviceextinfo );
export_servicegroups ( $objects->list_servicegroups() );
#export_servicedependencies ( $objects->list_servicedependencies );

exit $ERRORS{'OK'};
