# Nagios Reader to Centreon CLAPI

"Nagios Reader to Centreon CLAPI" is a free and open source project to analyse
Nagios CFG configuration files and to transform monitoring configuration to
Centreon CLAPI command in order to import configuration into Centreon web
interface.

## Prerequisites

First of all you need a Centreon server installed and ready to use. Please see the
document on htt://document.centreon.com to install a Centreon server based on ISO or RPM.

## Installation

This script uses the Perl-Nagios-Object library to read CFG files. To install
it please follow this steps on your Nagios(R) server:

    $ yum install perl-Module-Build perl-Test-Exception perl-Test-NoWarnings perl-List-Compare
	$ cd /tmp
	$ wget http://search.cpan.org/CPAN/authors/id/D/DU/DUNCS/Nagios-Object-0.21.20.tar.gz
	$ tar xzf Nagios-Object-0.21.20.tar.gz
	$ cd Nagios-Object-0.21.20
	$ perl Build.PL
    $ ./Build
    $ ./Build test
    $ ./Build install

Note : perl-List-Compare is from EPEL repo for CentOS/Red Hat

## Usage

To display help use the command:

    $ perl nagios_reader_to_centreon_clapi.pl --help
    ######################################################
    #    Copyright (c) 2005-2017 Centreon                #
    #    Bugs to http://github.com/nagiosToCentreon      #
    ######################################################
    
    Version: 3.0.0
    Usage: nagios_reader_to_centreon_clapi.pl
        -C (--config)      Path to nagios configuration files (must be a directory) (Default: /usr/local/nagios/etc/)
        -V (--version)     Nagios version of the configuration files (Default: 3)
        -P (--poller)      Name of the targeted poller (Default: Central)
        -p (--prefix)      Add a prefix before commands, contacts, templates, groups, etc.
        -s (--switch)      Switch alias and name of contacts for the configurations that need it
        -f (--filter)      Filter files to process with regexp (Default: '^(?!(\.|connector\.cfg))(.*\.cfg)$')
        -h (--help)        Usage help

To run the script please use the following command:

    $ perl nagios_reader_to_centreon_clapi.pl --config /usr/local/nagios/etc/ > /tmp/centreon_clapi_import_commands.txt

Export the file /tmp/centreon_clapi_import_commands.txt on your Centreon server.

Run the following command to import configuration into Centreon on your Centreon server:

    $ /usr/share/centreon/bin/centreon -u admin -p @PASSWORD -i /tmp/centreon_clapi_import_commands.txt

## Notes

- Services by hostgroups will be transformed : a template of 
service will be created using old service definition, and a unitary service will be created for all hosts linked to the hostgroup using the newly created service template.
- Hostgroups exclusions (i.e. hostgroup_name !Windows) won't be taken into account.
- Using filters may provoque errors at CLAPI import because of the contacts definition on several objects being the full name instead of the login/alias as CLAPI intend it to be.
