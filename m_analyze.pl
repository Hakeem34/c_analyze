#/**
# * Copyright 2023 Tatsuya Kubota
# *
# * Licensed under the Apache License, Version 2.0 (the "License");
# * you may not use this file except in compliance with the License.
# * You may obtain a copy of the License at
# *
# *     http://www.apache.org/licenses/LICENSE-2.0
# *
# * Unless required by applicable law or agreed to in writing, software
# * distributed under the License is distributed on an "AS IS" BASIS,
# * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# * See the License for the specific language governing permissions and
# * limitations under the License.
# */
#############################################################################
# ���W���[����̓X�N���v�g
#
#
#############################################################################

use strict;
use warnings;

use File::Basename;
use File::Path;
use File::Copy;
use Class::Struct;
use Cwd;
use Digest::MD5;


my $setting_file     = "m_analyze_setting.txt";
my $output_fld       = "m_analyze";
my $log_file_name    = "";                      #/* ���O�t�@�C����     */
my $org_std_out;
my $default_log      = 0;                       #/* �f�t�H���g���O�o�� */
my $module_name      = "sample";
my $output_temp_text = 0;                       #/* ���`����C�R�[�h���t�@�C���ɏo�͂��� */
my $jar_path         = "";                      #/* JAVA���N������PU�t�@�C���𐶐����� */
my @target_files = ();


&main();

#/*****************************************************************************/
#/* �T�u�f�B���N�g���̐���                                                    */
#/*****************************************************************************/
sub make_directory
{
    (my $dirname) = @_;

#   print "make dir : $dirname\n";

    #/* ���Ƀf�B���N�g�������݂��Ă��邩�H */
    if (! -d $dirname ){

        #/* �umkpath�v�����s�����ꍇ�A��O����������̂Łueval�v�ň͂� */
        eval{
            #/* �f�B���N�g���̍쐬(File::Path) */
            mkpath($dirname);
        };

        #/* �umkpath�v�̗�O�̓��e�́u$@�v�ɃZ�b�g����� */
        if( $@ ){
            die "$dirname creace err -> $@\n";
        }
    }
}


#/*****************************************************************************/
#/* �Ώۃt�@�C���̌���                                                        */
#/*****************************************************************************/
sub find_c_files
{
	my $target_dir = $_[0];
	my $dh;

	opendir($dh, $target_dir) || die "Can't opendir $target_dir: $!";
	while (readdir($dh))
	{
#		print "$_\n";
		my $entry = $_;

		if (($entry eq "\.") or ($entry eq "\.\."))
		{
			#/* skip */
		}
		elsif (-d $entry)
		{
			find_c_files($target_dir . "\\" . $entry);
		}
		else
		{
			if ($entry =~/\.[cChH]$/)         #/* ".c"�܂���",h"�ŏI����Ă��� */
			{
				print ("$target_dir" . "\\" . "$entry\n");
				push @target_files, $target_dir . "\\" . $entry;
			}
		}
	}
	closedir($dh)
}


#/*****************************************************************************/
#/* �R�}���h���C���I�v�V�����̉��                                            */
#/*****************************************************************************/
sub check_command_line_option
{
	my $option = "";

	if (@ARGV == 0)
	{
#		die "Usage: perl m_analyze.pl [module file]\n";
		print "analyze module by default setting.txt\n";
	}

	foreach my $arg (@ARGV)
	{
#		print "$arg\n";

		if ($option eq "s")
		{
			$setting_file = $arg;
			$option = "";
		}
		elsif ($option eq "o")
		{
			$output_fld = $arg;
			$option = "";
		}
		elsif ($option eq "l")
		{
			$log_file_name = $arg;
			$option = "";
		}
		elsif ($arg eq "-s")
		{
			$option = "s";
		}
		elsif ($arg eq "-l")
		{
			$option = "l";
		}
		elsif ($arg eq "-o")
		{
			$option = "o";
		}
		elsif ($arg eq "-t")
		{
			$output_temp_text = 1;
		}
		elsif ($arg eq "-dl")
		{
			$default_log = 1;
		}
		else
		{
			if (-d $arg)
			{
				find_c_files($arg);
			}
			else
			{
				push @target_files, $arg;
			}
		}
	}
}


#/*****************************************************************************/
#/* �ݒ�t�@�C���̓ǂݍ��ݏ���                                                */
#/*****************************************************************************/
sub read_setting_file
{
	if (!open(SETTING_IN, $setting_file))
	{
		print "cannot open file $setting_file\n";
		return;
	}

	while ( <SETTING_IN> )
	{
		my $line_text = $_;
#		print $line_text;

		if ($line_text =~ /^source\s+(.+)\n/)
		{
			push @target_files, $1;
		}
		elsif ($line_text =~ /^plantuml[ \t]+([^\s]+)/)
		{
			print "plantuml.jar path specified.\n";
			$jar_path = $1;
		}
		elsif ($line_text =~ /^module_name[ \t]+([^\s]+)/)
		{
			print "module name [$1] specified.\n";
			$module_name = $1;
		}
	}
	close(SETTING_IN);
}



#/*****************************************************************************/
#/* ���C���֐�                                                                */
#/*****************************************************************************/
sub main
{
	# ���̕W���o�͂�ۑ�����
	open(my $orig_stdout, ">&STDOUT") or die "Cannot save STDOUT: $!";

	&check_command_line_option();
	make_directory($output_fld);
	&read_setting_file();

	if ($log_file_name ne "")
	{
		my $log_path = $output_fld . "/" . $log_file_name;
		open STDOUT, ">>$log_path" or die "Can't create log file!\n";
	}
	elsif ($default_log == 1)
	{
		my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime();
		my $timestamp = sprintf("%04d%02d%02d_%02d%02d%02d", $year+1900, $mon+1, $mday, $hour, $min, $sec);
		my $log_path = $output_fld . "/m_analyze_log_" . $timestamp . ".log";
		open STDOUT, ">$log_path" or die "Can't create log file!\n";
	}

#	print "--------------------------------------------------------------------------------\n";
#	print " start analyzing $source_file\n";
#	print "--------------------------------------------------------------------------------\n";
	foreach my $source_file (@target_files)
	{
		print $orig_stdout "  analyzing $source_file\n";
		system("perl c_analyze.pl -o $output_fld $source_file");
	}

	exit (0);
}



