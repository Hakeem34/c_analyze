#/**
# * Copyright 2021 Tatsuya Kubota
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
# C言語プログラム解析スクリプト
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

use constant CONT_SIZE => "<b><size:20>";
use constant SENTENCE_CONTROL => 0;
use constant SENTENCE_DECLARE => 1;
use constant SENTENCE_FORMULA => 2;
use constant SENTENCE_UNKNOWN => 3;


#/* スクリプト動作の設定 */
my $output_temp_text = 0;		#/* 整形したCコードをファイルに出力する */
my $jar_path = "";				#/* JAVAを起動してPUファイルを生成する */

struct GlobalInfo => {
	lines        => '$',       #/* 行数                       */
	comment      => '$',       #/* コメント行数               */
	indent       => '$',       #/* 現在のインデント           */
	section      => '$',       #/* 現在のセクション           */
	in_function  => '$',       #/* 現在のスコープ             */
	bracket_type => '$',       #/* 現在の{}タイプ             */
};


#/* マクロ */
struct Macros => {
	name         => '$',       #/* マクロ名                   */
	value        => '$',       #/* 定義内容                   */
	is_func      => '$',       #/* 関数かどうか               */
	args         => '@',       #/* 引数                       */
};


#/* 関数を表す構造体 */
struct Functions => {
	name	   => '$',       #/* 関数名                     */
	lines      => '$',       #/* 行数                       */
	texts      => '@',       #/* 原文                       */
	steps      => '$',       #/* 実効ステップ数             */
	path	   => '$',       #/* メインパス                 */
	static     => '$',       #/* スタティックか？           */
	ret_typ    => '$',       #/* 戻り値                     */
	args_typ   => '@',       #/* 引数型                     */
	args_name  => '@',       #/* 引数名                     */
	write_args => '@',       #/* ポインタ引数に書き込むか？ */
	var_read   => '@',       #/* リードする変数             */
	var_write  => '@',       #/* ライトする変数             */
	func_call  => '@',       #/* コールする関数             */
	func_ref   => '@',       #/* 参照されている関数         */
	comment    => '$',       #/* コメント行数               */
	summary    => '$',       #/* 概要コメント               */
	make_tree  => '$',       #/* Tree展開済み               */
	label      => '@',       #/* ラベル                     */
	local_val  => '@',       #/* ローカル変数               */
	typedefs   => '%',
};


#/* 実行パスを表す構造体。分岐しない一連の処理 */
struct Path => {
	function   => '$',       #/* 所属する関数               */
	lines      => '$',       #/* 行数                       */
	type       => '$',       #/* パス種別                   */
	texts      => '@',       #/* 原文                       */
	pu_block   => '$',       #/* 処理ブロック               */
	call_block => '$',       #/* ブロック内の関数コール有無 */
	pu_text    => '@',       #/* アクティビティ図用         */
	steps      => '$',       #/* 実効ステップ数             */
	parent     => '$',       #/* 親パス                     */
	child      => '@',       #/* 子パス                     */
	var_read   => '@',       #/* リードする変数             */
	var_write  => '@',       #/* ライトする変数             */
	func_call  => '@',       #/* コールする関数             */
	indent     => '$',       #/* 親に戻るインデント         */
	backward   => '$',       #/* for文の繰り返し処理        */
	switch_val => '$',       #/* switch文の評価値           */
	case_count => '$',       #/* caseラベルの数             */
	case_val   => '@',       #/* caseラベルの値             */
	break      => '$',       #/* break終端か否か？          */
	comment    => '$',       #/* コメント行数               */
	level      => '$',       #/* パスレベル                 */
};

#/* 変数を表す構造体 */
struct Variables => {
	name        => '$',       #/* 変数名                     */
	typ         => '$',       #/* 型                         */
	init_val    => '$',       #/* 初期値                     */
	extern      => '$',       #/* 外部変数か？               */
	static      => '$',       #/* スタティックか？           */
	const       => '$',       #/* 定数か？                   */
	func_read   => '@',       #/* リードする関数             */
	func_write  => '@',       #/* ライトする関数             */
	section     => '$',       #/* section指定                */
	forcus      => '$',       #/* 詳細解析対象か？           */
	comment_txt => '$',       #/* コメント                   */
};


struct CurrentSentence => {
	text       => '$',       #/* 原文                       */
	name       => '$',       #/* 変数/関数名                */
	typ        => '$',       #/* 型                         */
	typ_fixed  => '$',       #/* 型確定                     */
	name_fixed => '$',       #/* 名称確定                   */

	init_val   => '$',       #/* 初期値                     */
	typedef    => '$',       #/* typedef文                  */
	struct     => '$',       #/* struct/union/enum          */
	extern     => '$',       #/* 修飾子extern有無           */
	static     => '$',       #/* 修飾子static有無           */
	const      => '$',       #/* 修飾子const有無            */
	unsigned   => '$',       #/* 修飾子unsigned有無         */
	words      => '@',       #/* 単語                       */
	position   => '$',       #/* 解析位置                   */
	astarisk   => '$',       #/* アスタリスク               */
	astarisk_f => '$',       #/* 関数ポインタのアスタリスク */
	astarisk_u => '$',       #/* 未判別のアスタリスク       */
	is_func    => '$',       #/* 関数？                     */
	arg_list   => '$',       #/* 引数リスト                 */

	clear      => '$',       #/* クリア実施フラグ           */
	backward   => '$',       #/* for文の繰り返し処理        */
	switch_val => '$',       #/* switch文の評価値           */
	pu_text    => '$',       #/* アクティビティ図用         */
	case_val   => '$',       #/* caseラベルの値             */
	func_call  => '$',       #/* 関数コールのフラグ         */
	case_cond  => '$',       #/*                            */
	sentence   => '$',       #/* 文のタイプ(式、宣言、制御) */
};



#/* ファイル間で共通の変数 */
my @c_prepro_word = ("include", "define", "undef", "pragma", "else", "endif", "elif", "ifdef", "ifndef", "error", "if");
my $output_fld = "c_analyze";
my @include_paths  = ();
my @extracts  = ();
my @target_include = ();
my @target_files = ();
my $setting_file = "c_analyze_setting.txt";
my $output_remain = "";
my @output_lines;
my @input_lines;


#/**********************************/
#/* ファイルごとに初期化必要な変数 */
#/**********************************/

#/* C言語の整形に使う変数 */
my $is_comment = 0;
my $is_single_comment = 0;
my $is_literal = 0;
my $line_postpone = "";
my $indent_level = 0;
my @valid_line = (1);
my @once_valid = (1);
my $nest_level   = 0;
my @macros = ();

#/* C言語の解析に使う変数 */
my @include_files  = ();
my @global_variables = ();
my @functions = ();
my $current_function = "";
my @path_stack = ();
my $current_path = "";
my $global_data = GlobalInfo->new();
my $current_sentence = CurrentSentence->new();
my $first_comment    = "";			#/* コメントブロックの最初     */
my $current_comment  = "";			#/* 直近のコメント（単行）     */
my $current_comments = "";			#/* 直近のコメント（累積）     */
my $current_brief    = "";			#/* 直近の@briefコメント       */
my $in_define = 0;
my @literals = ();
my %global_typedefs = ();			#/* グローバルの型定義のハッシュ */

my @prepare_funcs = (\&comment_parse, \&line_backslash_parse, \&line_define_parse, \&line_parse_1st, \&line_parse_2nd, \&line_indent_parse);

#/* 制御文（必ずセンテンスの先頭に来るはず、、、） */
my %analyze_controls = (
                        'if'      => \&analyze_if,      'else'    => \&analyze_else,      'do'       => \&analyze_do,       '{'       => \&analyze_bracket_open,
                        'break'   => \&analyze_break,   'case'    => \&analyze_case,      'continue' => \&analyze_continue, '}'       => \&analyze_bracket_close,
                        'goto'    => \&analyze_goto,    'for'     => \&analyze_for,       'switch'   => \&analyze_switch,   'default' => \&analyze_default,
                        'while'   => \&analyze_while,   'return'  => \&analyze_return
                    );

my %analyze_in_funcs = (
                        '('       => \&analyze_round_bracket_open,
                        ':'       => \&analyze_colon,   ';'       => \&analyze_semicolon, '?'        => \&analyze_ternary,
                    );

&main();

sub init_variables
{
	$is_comment = 0;
	$is_single_comment = 0;
	$is_literal = 0;
	$line_postpone = "";
	@macros = ();
	@include_files  = ();
	@global_variables = ();
	@functions = ();
	$current_function = "";
	@path_stack = ();
	$current_path = "";
	$global_data = GlobalInfo->new();
	$global_data->lines(0);
	$global_data->comment(0);
	$global_data->indent(0);
	$global_data->section("default");
	$global_data->in_function(0);
	$global_data->bracket_type("none");
	$current_sentence = CurrentSentence->new();
	$first_comment    = "";			#/* コメントブロックの最初     */
	$current_comment  = "";			#/* 直近のコメント（単行）     */
	$current_comments = "";			#/* 直近のコメント（累積）     */
	$current_brief    = "";			#/* 直近の@briefコメント       */
	$in_define = 0;
	@literals = ();
	@valid_line = (1);
	@once_valid = (1);
	$nest_level   = 0;
	$indent_level = 0;
	%global_typedefs = ();			#/* 型定義のハッシュ */
}


#/* コマンドラインオプションの解析 */
sub check_command_line_option
{
	my $option = "";

	foreach my $arg (@ARGV)
	{
		print "$arg\n";

		if ($option eq "s")
		{
			$setting_file = $arg;
			$option = "";
		}
		elsif ($arg eq "-s")
		{
			$option = "s";
		}
		elsif ($arg eq "-t")
		{
			$output_temp_text = 1;
		}
		else
		{
			push @target_files, $arg;
		}
	}
}


#/* 1行テキスト出力 */
sub output_line
{
	my $local_line = $output_remain . $_[0];
	$output_remain = "";

#	if ($output_temp_text)
#	{
#		print "input : $local_line\n";
#		print OUT_FILE_OUT $local_line;
#	}

	while ($local_line =~/^([^\n]*)\n/)
	{
		my $front = $1;
		$local_line =~ s/^([^\n]*)\n//;
#		print "front : $front\n\n";
		push @output_lines, "$front\n";
	}

	if ($local_line ne "")
	{
		if ($local_line =~ /\n/) {
#			print "end   : $local_line\n";
			push @output_lines, $local_line;
		}
		else
		{
			$output_remain = $local_line;
		}
	}
}


#/* メイン関数 */
sub main
{
	if (@ARGV == 0)
	{
		die "Usage: perl c_analyze.pl [source file] -s [setting file]\n";
	}

	&check_command_line_option();
	foreach my $source_file (@target_files)
	{
		print "--------------------------------------------------------------------------------\n";
		print " start analyzing $source_file\n";
		print "--------------------------------------------------------------------------------\n";
		&init_variables();
		&analyze_source($source_file);
	}

	exit (0);
}



sub pre_proc_c_file
{
	my $out_file     = "";
	my $source_file  = $_[0];
	my $proc_num     = $_[1] + 1;
	my $index        = 0;

#	if ($output_temp_text)
#	{
#		$out_file = $output_fld . "/" . basename($source_file) . "_temp$proc_num.txt";
#		open(OUT_FILE_OUT,">$out_file")   || die "Can't create out file.\n";
#	}

	print "-----------------\n";
	print "start file[$proc_num]!\n";
	print "-----------------\n";

	if ($proc_num == 3)
	{
		#/* 先に置き換えたリテラルを#define定義する */
		for ($index = 0; $index < @literals; $index++)
		{
			&output_line("#define __C_ANALYZE_LITERALS_$index" . " " . $literals[$index] . "\n");
		}
	}
}


sub post_proc_c_file
{
	my $out_file     = "";
	my $source_file  = $_[0];
	my $proc_num     = $_[1] + 1;
	my $local_line   = "";

	if ($output_temp_text)
	{
#		close(OUT_FILE_OUT);

		$out_file = $output_fld . "/" . basename($source_file) . "_temp_mem_$proc_num.txt";
		open(OUT_FILE_OUT,">$out_file")   || die "Can't create out file.\n";
		foreach $local_line (@output_lines)
		{
			print OUT_FILE_OUT $local_line;
		}
		close(OUT_FILE_OUT);
	}

	$line_postpone = "";
	$output_remain = "";
	@input_lines = @output_lines;
	@output_lines = ();
}


#/* 解析前にCコードを成形する */
sub prepare_c_file
{
	my $source_file  = $_[0];
	my $loop = 0;
	my $local_line   = "";

	@output_lines = ();
	@input_lines  = ();
	open(SOURCE_IN,"$source_file") || die "Can't open source file. $source_file\n";
	while ( <SOURCE_IN> )
	{
		push @input_lines, $_;
	}
	close(SOURCE_IN);


	for ($loop = 0; $loop < 6; $loop++)
	{
		my $proc_ptr = $prepare_funcs[$loop];

		&pre_proc_c_file($source_file, $loop);
		
		foreach $local_line (@input_lines)
		{
			$proc_ptr->($local_line);
		}

		&post_proc_c_file($source_file, $loop);
	}
}



#/* １モジュール解析 */
sub analyze_source
{
	my $out_file     = "";
	my $source_file  = $_[0];
	my $local_line;

	make_directory($output_fld);
	&read_setting_file();
	@output_lines = ();

	#/* Cコードの事前整理 */
	&prepare_c_file($source_file);

	$out_file = $output_fld . "/" . basename($source_file) . "_analyzed.csv";
	open(OUT_FILE_OUT,">$out_file")   || die "Can't create analyzed file.\n";

	#/* C言語解析 */
	print "-----------------\n";
	print "Analyzing module \n";
	print "-----------------\n";
	&clear_current_sentence();
	$first_comment    = "";
	$current_comment  = "";
	$current_comments = "";
	$current_brief    = "";
	foreach $local_line (@input_lines)
	{
		$global_data->lines($global_data->lines+1);
		&analyze_module($local_line);
	}


	print "----------------------------\n";
	print "Analyzing! static reference \n";
	print "----------------------------\n";
	my $function;
	foreach $function (@functions)
	{
		&check_reference($function);
	}

	print "---------------\n";
	print "Out Result!    \n";
	print "---------------\n";
	&output_result($source_file);

	close(OUT_FILE_OUT);
}


#/****************************/
#/* サブディレクトリの生成   */
#/****************************/
sub make_directory
{
    (my $dirname) = @_;

#   print "make dir : $dirname\n";

    #/* 既にディレクトリが存在しているか？ */
    if (! -d $dirname ){

        #/* 「mkpath」が失敗した場合、例外が発生するので「eval」で囲む */
        eval{
            #/* ディレクトリの作成(File::Path) */
            mkpath($dirname);
        };

        #/* 「mkpath」の例外の内容は「$@」にセットされる */
        if( $@ ){
            die "$dirname creace err -> $@\n";
        }
    }
}



#/* エスケープ文字を考慮しつつ、クォーテーションのクローズ位置を探す */
sub find_quatation
{
	my $quatation = $_[0];
	my $string    = $_[1];
	my $loop      = 0;
	my $char;

	for ($loop = 0; $loop <= length($string); $loop++)
	{
		$char = substr($string, $loop, 1);
		if ($char eq $quatation)
		{
#			print "find quatation! $quatation, $string, $loop\n";
			return $loop;
		}
		elsif ($char eq "\\")
		{
			$loop++;
		}
	}

	return -1;
}

#/* コメントの分離処理 */
sub comment_parse
{
#	print "enter : $_[0]line_postpone : $line_postpone\n";

	my $local_line = $line_postpone . $_[0];
	$line_postpone = "";

	if ($is_single_comment == 1)
	{
		#/* 1行コメントの継続 */
		if ($local_line =~/\\\s*\n/)         #/* '\'で終わっている */
		{
			#/* さらに継続の場合 */
			$local_line =~ s/(.*)\\\s*\n/$1/g;
			$local_line =~ s/\/\*/\/ \*/g;
			$local_line =~ s/\*\//\* \//g;
			&output_line("/* " . $local_line . " */\n");
#			print "Single comment gose next line!\n";
			$is_single_comment = 1;
		}
		else
		{
			#/* この行で完結。// コメントの後ろに、"/*" か "*/"の記載があれば、無理やりスペースを挿入する */
			$local_line =~ s/\n//g;
			$local_line =~ s/\/\*/\/ \*/g;
			$local_line =~ s/\*\//\* \//g;
			&output_line("/* " . $local_line . " */\n");
			$is_single_comment = 0;
		}
	}
	elsif ($is_comment == 1)
	{
		#/* コメント行の継続 */
		if ($local_line =~/(\*\/)/)
		{
			my $line_rear = $';
			$is_comment = 0;
			&output_line("/* " . $` . " */\n");

			if ($line_rear =~ /[^\s]/)
			{
				&comment_parse($line_rear);
			}
		}
		else
		{
			$local_line =~ s/\n//g;
			&output_line("/* " . $local_line . " */\n");
		}
	}
	elsif ($local_line =~/(\/\/|\/\*|\"|\')/)
	{
		#/* コメントまたはリテラルの始まり */

		my $line_front = $`;
		my $line_rear = $';
		if ($1 eq "\/\/")
		{
#			print "Single Line Comment! $line_rear\n";

			if ($local_line =~/(\\\s*\n)/)
			{
#				print "Single comment goes next line!\n";
				$is_single_comment = 1;
				$local_line = $line_front . "\n";
				&output_line($line_postpone . $local_line);
				$line_rear =~ s/(.*)\\\s*\n/$1/g;
				$line_rear =~ s/\/\*/\/ \*/g;
				$line_rear =~ s/\*\//\* \//g;
				&output_line("/* " . $line_rear . " */\n");
			}
			else
			{
				$is_single_comment = 0;
				$local_line = $line_front . "\n";
				$line_rear =~ s/\n//g;
				$line_rear =~ s/\/\*/\/ \*/g;
				$line_rear =~ s/\*\//\* \//g;
				&output_line("/* " . $line_rear . " */\n");

				$local_line = $line_postpone . $local_line;
				if ($local_line =~ /[^\s]/)
				{
					&output_line($local_line);
				}
			}

			$line_postpone = "";
		}
		elsif ($1 eq "\'")
		{
			my $index = index($local_line, "\'");
			my $length = &find_quatation("\'", $line_rear);

			if ($length > 0)
			{
				#/* 同じ行で閉じている場合は、置き換えて再帰処理する */
				my $local_literal = substr($local_line, $index, $length + 2);
				my $literal_num = @literals;
				push @literals, $local_literal;
				substr($local_line,  $index, length($local_literal), "__C_ANALYZE_LITERALS_$literal_num");
				&comment_parse($local_line);
			}
			elsif ($line_rear =~/\\\s*\n/)
			{
				#/* バックスラッシュで次行に持ち越している場合は、処理保留 */
				$local_line =~ s/\\\s*\n//;
				$line_postpone = $local_line;
				print "line_postpone : $line_postpone\n";
			}
			else
			{
				die "missing terminating \" character3\n$local_line";
			}
		}
		elsif ($1 eq "\"")
		{
			my $index = index($local_line, "\"");
			my $length = &find_quatation("\"", $line_rear);

			if ($length == 0)
			{
				#/* 空文""だった場合は、置き換えて再帰処理する */
				my $local_literal = "\"\"";
				my $literal_num = @literals;
				push @literals, $local_literal;
				substr($local_line,  $index, length($local_literal), "__C_ANALYZE_LITERALS_$literal_num");
				&comment_parse($local_line);
			}
			elsif ($length > 0)
			{
				#/* 同じ行で閉じている場合は、置き換えて再帰処理する */
#				my $local_literal = "\"$`$1\"";
				my $local_literal = substr($local_line, $index, $length + 2);
				my $literal_num = @literals;
				push @literals, $local_literal;
				substr($local_line,  $index, length($local_literal), "__C_ANALYZE_LITERALS_$literal_num");
				&comment_parse($local_line);
			}
			elsif ($line_rear =~/\\\s*\n/)
			{
				#/* バックスラッシュで次行に持ち越している場合は、処理保留 */
				$local_line =~ s/\\\s*\n//;
				$line_postpone = $local_line;
				print "line_postpone : $line_postpone\n";
			}
			else
			{
				die "missing terminating \" character2\n$local_line";
			}
		}
		else
		{
#			print "C Style Comment! $local_line\n";
			if ($' =~/(\*\/)/)
			{
				&output_line("/* " . $` . " */\n");
				$local_line = $line_front . $';
				
				if ($local_line =~ /[^\s]/)
				{
					&comment_parse($local_line);
				}
			}
			else
			{
				$is_comment = 1;
				$local_line = $line_front;
				&output_line($line_postpone . $local_line . "\n");

				$line_rear =~ s/\n//g;
				$line_rear =~ s/\/\*/\/ \*/g;
				$line_rear =~ s/\*\//\* \//g;
				&output_line("/* " . $line_rear . " */\n");
				$line_postpone = "";
			}
		}
	}
	else
	{
		&output_line($line_postpone . $local_line);
		$line_postpone = "";
	}
}


#/* 有効なdefineマクロかどうか */
sub is_valid_macro
{
	my $define;

	foreach $define (@macros)
	{
		if ($_[0] eq $define->name)
		{
			return 1;
		}
	}

	return 0;
}


#/* 該当行がコメントかどうか */
sub is_comment_line
{
	my $local_line = $_[0];

	if ($local_line =~ /^\/\*.*\*\/\n/)
	{
#		print "comment!!! $local_line\n";
		return 1;
	}
	
	return 0;
}


sub check_bracket_close
{
	my $text  = $_[0];
	my $open  = $_[1];
	my $close = $_[2];
	my $position = 0;
	my $count = 0;
	my $open_idx;
	my $close_idx;

	while (1)
	{
		$open_idx = index($text, $open, $position);
		$close_idx = index($text, $close, $position);
		if ( ($open_idx < 0) && ($close_idx < 0) )
		{
			#/* 括弧がなくなればOK */
			return ($count == 0);
		}
		else
		{
			if ($open_idx < 0)
			{
				#/* Closeだけが残っている場合 */
				$count--;
				$position = $close_idx + 1;
			}
			elsif ($close_idx < 0)
			{
				#/* Openだけが残っている場合。継続するまでもなく、クローズしていない */
				return 0;
			}
			else
			{
				#/* Open, Close両方が残っている場合 */
				if ($open_idx < $close_idx)
				{
					$count++;
					$position = $open_idx + 1;
				}
				else
				{
					$count--;
					$position = $close_idx + 1;
				}
			}

			#/* 途中でカウントがマイナスになったらおかしい！ */
			($count >= 0) or die "strange bracket count!\n";
		}
	}
}

#/* \による行連結を解除 */
sub line_backslash_parse
{
	my $local_line = $_[0];
	my $index;

	#/* コメント行はそのまま出力 */
	if (&is_comment_line($local_line))
	{
		&output_line($local_line);
		return;
	}


	$local_line = $line_postpone . $_[0];
	$line_postpone = "";

	#/* \で終わっている行は持ち越す */
	if ($local_line =~ /\\\s*\n/)
	{
		$line_postpone = $`;
	}
	else
	{
		if ($local_line =~ /^\s*\#/)
		{
			#/* ディレクティブは除外 */
		}
		else
		{
			if ($local_line =~ /([\;\:\{\}])\s*\n/)
			{
				#/* ; か : か { か } で終わっている行は、末尾のスペースを除去 */
#				print "not joint $local_line\n";
				$local_line =~ s/([\;\:\{\}])\s*\n/$1\n/
			}
		}
	}

	if ($line_postpone eq "")
	{
		#/* 行頭の処理がめんどうなので、とりあえず半角スペースをつけてしまう */
		$local_line = " " . $local_line;
		&output_line($local_line);
	}
}


#/* 置き換えたリテラルを復元する */
sub restore_literal
{
	my $text  = $_[0];
	
	while ($text =~ /__C_ANALYZE_LITERALS_([0-9]+)/)
	{
		my $literal = $literals[$1];
		$text =~ s/__C_ANALYZE_LITERALS_$1/$literal/;
	}

	return $text;
}


#/* (), {}, []などのネストを考慮して内部を抽出する */
sub extract_bracket_text
{
	my $text  = $_[0];
	my $open  = $_[1];
	my $close = $_[2];
	my $count = 1;
	my $position = 0;

	my $open_idx;
	my $close_idx;

	while ($count > 0)
	{
		$open_idx = index($text, $open, $position);
		$close_idx = index($text, $close, $position);

		($close_idx >= 0) or die "not closed bracket! $text $open $close\n";
		if (($open_idx == -1) ||
			($open_idx > $close_idx))
		{
			$count--;
			$position = $close_idx + 1;
		}
		else
		{
			$count++;
			$position = $open_idx + 1;
		}
	}

#	print "extract_bracket! $position, $text\n";
	return substr($text, 0, $position - 1);
}


sub check_extracts
{
	my $text = $_[0];
	my $check = "";

	foreach $check (@extracts)
	{
		if ($check eq $text)
		{
			return 1;
		}
	}

	return 0;
}


#/* defineマクロの置き換え実施 */
sub replace_macro
{
	my $text          = $_[0];
	my $only_extracts = $_[1];       #/* 指定されたマクロのみを展開するかどうか */
	my $define;
	my $value;
	my $index;
	my $count;
	my @args;

#	print "replace [$text] to\n";
	$count = @macros;
	for ($index = 0; $index < $count; $index++)
	{
		$define = $macros[$index]->name;
		$value  = $macros[$index]->value;
		@args   = @{$macros[$index]->args};
		
		if ($only_extracts)
		{
			if (check_extracts($define) == 0)
			{
				#/* 展開対象に指定されていなければ、スキップする */
				next;
			}
		}

		if ($macros[$index]->is_func == 1)
		{
#			print "$define is MACRO FUNC! : $text\n";
			my $parameter;
			my @parameters;
			my $argument;
			my $loop;
			if ($text =~ /($define\s*\()/)
			{
				my $replace = $1;

				#/* まず引数のテキストを抽出する */
				$parameter = &extract_bracket_text($', "\(", "\)");
#				print "MACRO FUNC CALL! $define($parameter)\n";
				$replace = $replace . $parameter . ")";
#				print "MACRO FUNC CALL! $replace\n";

				#/* 続いて引数をばらして配列に格納 */
				@parameters = &analyze_parameter_list($parameter);

#				print "value before @parameters : $value\n";
				for ($loop = 0; $loop < @{$macros[$index]->args}; $loop++)
				{
					$argument = $args[$loop];
#					print "arg : $argument, param : $parameters[$loop]\n";
					$value =~ s/$argument/$parameters[$loop]/g;
				}
#				print "value after @parameters : $value\n";

				#/* マクロ全体を置き換え */
#				print "macro is $define\($parameter\)\n";
#				print "value is $value\n";
#				print "text before $text\n";
				$parameter  = quotemeta($parameter);
				if ($text =~ /$define\s*\($parameter\)/)
				{
#					print "hit macro1!!!!!\n";
				}
				if (index($text, $replace) >= 0)
				{
#					print "hit macro2!!!!!\n";
					substr($text,  index($text, $replace), length($replace), $value);
				}
				if (index($text, "$define($parameter)") >= 0)
				{
#					print "hit macro3!!!!!\n";
				}
				
				$text =~ s/$define\s*\($parameter\)/$value/g;
#				print "text after  $text\n";
			}
		}
		else
		{
			$text =~ s/$define/$value/g;
		}
	}
#	print "[$text]\n";

	return $text;
}


#/* ,で区切られた引数リストを識別して配列で返す */
sub analyze_parameter_list
{
	my $text  = $_[0];
	my @ret_val = ();

	if ($text =~ /#/)
	{
		die "stray '#' in program($text)\n";
	}

	while ($text =~ /([^,]+),/)
	{
#		print "macro param $1\n";
		push @ret_val, $1;
		$text = substr($text, index($text, ",") + 1);
	}

#	print "macro param $text\n";
	push @ret_val, $text;
	return @ret_val;
}


#/* マクロ仮引数の解析 */
sub analyze_macro_arg_list
{
	my $text  = $_[0];
	my @ret_val = ();

	while ($text =~ /([_A-Za-z][_A-Za-z0-9]*)\s*,/)
	{
		push @ret_val, $1;
		$text = substr($text, index($text, ",") + 1);
	}

	if ($text =~ /([_A-Za-z][_A-Za-z0-9]*)/)
	{
		push @ret_val, $1;
	}
	elsif ($text =~ /\.\.\./)
	{
		push @ret_val, "...";
	}

	return @ret_val;
}


#/* マクロ定義の追加処理 */
sub new_macro
{
	my $name  = $_[0];
	my $value = $_[1];
	my $args =  $_[2];
	my $defined;
	my $local_macro;
	my $index;

	foreach $defined (@macros)
	{
		if ($defined->name eq $name)
		{
			return;
		}
	}

	$local_macro = Macros->new();
	$local_macro->name($name);
	$local_macro->value($value);
	if ($args eq "")
	{
		$local_macro->is_func(0);
		@{$local_macro->args} = ();
	}
	else
	{
#		print "new MACRO FUNC! $name($args)\n";
		$local_macro->is_func(1);
		@{$local_macro->args} = &analyze_macro_arg_list($args);
#		printf("macro args : @{$local_macro->args}\n");
	}

	if (@macros == 0)
	{
		push @macros, $local_macro;
	}
	else
	{
		for ($index = 0; $index < @macros; $index++)
		{
			if (length($macros[$index]->name) < length($name))
			{
				#/* 長い順にソートして配列にしていく */
				splice(@macros,  $index, 0, $local_macro);
				return;
			}
		}

		#/* 最短であった場合は末尾に足す */
		push @macros, $local_macro;
	}
}


#/* ディレクティブの処理 */
sub line_define_parse
{
	my $local_line = $_[0];
	my $prepro;
	my $define;
	my $valid_now;
	
	$valid_now = is_valid_now();

	#/* コメント行はそのまま出力 */
	if (&is_comment_line($local_line))
	{
		if ($valid_now == 1)
		{
			&output_line($local_line);
		}
		return;
	}

	#/* プリプロセッサの処理 */
#	print "define parse : $local_line";
	foreach $prepro (@c_prepro_word)
	{
		if ($local_line =~/#\s*$prepro/)
		{
			#/* とりあえず先頭と#の後ろの余計なスペースを除去 */
#			print "input  : $local_line";
			$local_line =~ s/\s*#\s*($prepro)/#$1/;
#			print "output : $local_line";
			if ($local_line =~/#$prepro[\-\!\+]/)
			{
				$local_line =~ s/(#$prepro)([\-\!\+])/$1 $2/;
			}
			
			if ($local_line =~ /\#define\s+([A-Za-z_][A-Za-z0-9_]*)\(([^\)]*)\)\s+(.*)\n/)
			{
				my $macro_name = $1;
				my $second_part = $3;

#				print "#define macro func! $macro_name($2) : $3\n";
				&new_macro("$macro_name", $3, $2);
				&output_line($local_line);
			}
			elsif ($local_line =~ /\#define\s+([A-Za-z_][A-Za-z0-9_]*)\s+(.*)\n/)
			{
				#/* マクロの定義 */
				if ($valid_now == 1)
				{
					my $macro_name = $1;
					my $second_part = $2;
					
#					print "#define macro! $macro_name : $second_part\n";
					&new_macro($macro_name, $second_part, "");
					&output_line($local_line);
				}
			}
			elsif ($local_line =~ /\#define\s+([A-Za-z_][A-Za-z0-9_]*)\s*\n/)
			{
				#/* マクロの定義 */
				if ($valid_now == 1)
				{
#					print "#define macro only! $1\n";
					&new_macro($1, "", "");

					&output_line($local_line);
				}
			}
			elsif ($local_line =~ /\#undef\s+([A-Za-z0-9_]*)/)
			{
				#/* マクロ定義の削除処理 */
				if ($valid_now == 1)
				{
					my $index;
#					print "\#undef! $1\n";
					for ($index = 0; $index < @macros; $index++)
					{
						if ($macros[$index]->name eq $1)
						{
							splice @macros, $index, 1;
							&output_line($local_line);
							return;
						}
					}

					&output_line($local_line);
#					print "$1 is not defined!\n"
				}
			}
			elsif ($local_line =~ /\#ifdef\s+([A-Za-z_][A-Za-z0-9_]*)/)
			{
				my $result;
#				print "#ifdef $1\n";
				$result = is_valid_macro($1);
				if ($result == 1)
				{
					push_valid_nest(1);
				}
				else
				{
					push_valid_nest(0);
				}
			}
			elsif ($local_line =~ /\#ifndef\s+(.*)/)
			{
				my $result;
#				print "#ifndef $1\n";
				$result = is_valid_macro($1);
				if ($result == 0)
				{
					push_valid_nest(1);
				}
				else
				{
					push_valid_nest(0);
				}
			}
			elsif ($local_line =~ /\#if\s+(.*)/)
			{
				my $result;
#				print "#if $1\n";
				$result = calc_text($1);

				if ($result =~ /[^\+\-0-9]/)
				{
					#/* 数値以外を含む */
#					print "not numeric! [$result]\n";
					push_valid_nest(0);
				}
				elsif ($result eq "")
				{
					#/* if条件がからっぽ */
##					print "empty condition!\n";
					push_valid_nest(0);
				}
				else
				{
					#/* 数値のみ */
#					print "numeric! $result\n";
					if ($result == 0)
					{
#						print "invalid #if\n";
						push_valid_nest(0);
					}
					else
					{
#						print "valid #if\n";
						push_valid_nest(1);
					}
				}
			}
			elsif ($local_line =~ /\#elif\s+(.*)/)
			{

				my $result;
#				print "#elif $1\n";
				turn_valid();
				
				$valid_now = is_valid_now();
				if ($valid_now == 1)
				{
					$result = calc_text($1);

					if ($result =~ /[^\+\-0-9]/)
					{
						#/* 数値以外を含む */
#						print "not numeric! [$result]\n";
						push_valid_nest(0);
					}
					else
					{
						#/* 数値のみ */
#						print "numeric! $result\n";
						if ($result == 0)
						{
#							print "invalid #if\n";
							push_valid_nest(0);
						}
						else
						{
#							print "valid #if\n";
							push_valid_nest(1);
						}
					}
				}
			}
			elsif ($local_line =~ /\#else/)
			{
				my $current;
				turn_valid();
				
				$current = is_valid_now();
#				print "#else!  is_valid : $current\n";
			}
			elsif ($local_line =~ /\#endif/)
			{
#				print "#endif!\n";
				pop_valid_nest();
			}
			elsif ($local_line =~ /\#error\s+(\S*)/)
			{
				if ($valid_now == 1)
				{
					$local_line = &restore_literal($local_line);
					die "#error in valid line! : $local_line";
				}
#				print "#error! $1\n";
			}
			else
			{
#				print "unknown prepro!\n";
				&output_line($local_line);
			}

			return;
		}
	}

	if ($valid_now == 1)
	{
		$local_line = $line_postpone . $_[0];
		$line_postpone = "";

		if (check_bracket_close($local_line, "(", ")"))
		{
			$local_line = replace_macro($local_line, 1);
			&output_line($local_line);
		}
		else
		{
			#/* ()が閉じていない行は連結する */
			$local_line =~ s/\n//;
			$line_postpone = $local_line;
		}
	}
}


sub line_indent_parse
{
	my $local_line = $_[0];
	my $prepro;

	#/* 先頭の空白を除去する */
	$local_line =~ s/^[ \t]+//;

	#/* コメント行はそのまま出力 */
	if (&is_comment_line($local_line))
	{
		&output_line($local_line);
		return;
	}

	#/* プリプロセッサの行はそのまま出力 */
	foreach $prepro (@c_prepro_word)
	{
		if ($local_line =~/#\s*$prepro/)
		{
			$local_line =~ s/#\s*($prepro)/#$1/;
			&output_line($local_line);
			return;
		}
	}

	$local_line =~ s/[ \t]+/ /g;                   #/* スペースとTABを一つのスペースに変換 */

	if ($local_line =~ /}/)
	{
		$indent_level--;
#		print "indend dec!!!!!!!!!!!!($indent_level) $local_line\n";
	}

	#/* インデント付加 */
#	print "before : $local_line\n";
	$local_line = ("    " x $indent_level) . $local_line;
#	print "after  : $local_line\n";

	if ($local_line =~ /{/)
	{
		$indent_level++;
#		print "indend inc!!!!!!!!!!!!($indent_level) $local_line\n";
	}

	&output_line($local_line);
}


sub find_bracket_close
{
	my $local_line = $_[0];
	my $index;

#	print "find bracket close $local_line";
	while($local_line =~ /\(([^\)]*)\)/)
	{
		$local_line =~ s/\(([^\)]*)\)/\<$1\>/g
	}

	$index = index($local_line, "\)");
#	print "find out by $index from $local_line";
	return index($local_line, "\)");
}


#/*  */
sub line_parse_1st
{
	my $local_line = $_[0];
	my $index;

	#/* コメント行はそのまま出力 */
	if (&is_comment_line($local_line))
	{
		&output_line($local_line);
		return;
	}

	if ($local_line =~ /^\s*\#/)
	{
		#/* ディレクティブは除外 */
		if ($line_postpone ne "")
		{
			#/* 持ち越しながらディレクティブが始まる場合は、マクロなど特殊な記述になっているので、改行して区切る */
			&output_line($line_postpone . "\n");
			$line_postpone = "";
		}
	}
	else
	{
		$local_line = $line_postpone . $local_line;
		$line_postpone = "";

		if ($local_line =~ /([^\;\{\}])\s*\n/)
		{
			#/* ; か { か } で終わってない行は、スペース1個空けて連結する */
#			print "joint $local_line\n";
			$line_postpone = "$`$1 ";
		}
	}

	if ($line_postpone eq "")
	{
		&output_line($local_line);
	}
}


sub line_parse_2nd
{
	my $local_line = $_[0];
	my $prepro;
	my $index_question = 0;
	my $index_colon    = 0;

	#/* コメント行はそのまま出力 */
	if (&is_comment_line($local_line))
	{
		&output_line($local_line);
		$current_comment = $local_line;
#		print "current_comment1 : $current_comment\n";
		return;
	}

	#/* ディレクティブ行はそのまま出力 */
	if ($local_line =~ /^#define|^#include|^#pragma/)
	{
		&output_line($local_line);
		return;
	}

	if ($current_comment ne "")
	{
		$current_comment = "";
		if ($local_line =~ /^\s*\n/)
		{
			#/* コメント行の直後の改行は温存する */
			&output_line("\n");
		}
	}

	$local_line =~ s/^\s*\n/ /;                   #/* スペースと改行だけの行は削除       */

	if ($local_line =~/^(\s*)\{\s*\n/)
	{
		#/* スペースと{だけの行はそのまま出力 */
		&output_line("$1\{\n ");
		return;
	}

	if ($local_line =~/^(\s*)(})\s*\n/)
	{
		#/* スペースと}だけの行はそのまま出力 */
		&output_line("$1$2\n ");
		return;
	}

	#/* {の前後に改行を挟む */
	$local_line =~ s/{/\n {\n /g;

	#/* }の前後に改行を挟む */
	$local_line =~ s/}/\n }\n /g;

	#/* ;の後ろに改行を挟む */
	$local_line =~ s/;/;\n /g;

	#/* とりあえず全部の:に改行をつける */
	$local_line =~ s/:/:\n /g;

	#/* 三項演算子?の後ろにある:は改行をキャンセルする */
	while ($local_line =~ /\?(.*):\n /)
	{
		$local_line =~ s/\?(.*):\n /\?$1:/g;
	}

	#/* else, do節の後ろは改行 */
	$local_line =~ s/(\s*)(else|do)([^_A-Za-z0-9])/$1$2\n $3/g;

	#/* if, while, for節の後ろは()が閉じたところで改行する */
	if ($local_line =~ /(\s*)(if|while|for)\s*\(/)
	{
		my $word = $2;
		my $index_close;
		my $before_bracket = "$`$1$2 \(";
		my $after_bracket = $';

		my $before_close;
		my $after_close;

#		print "$before_bracket$after_bracket\n";
		$index_close = &find_bracket_close($after_bracket);

		$before_close = substr($after_bracket, 0, $index_close);
		$after_close  = substr($after_bracket, $index_close + 1);
#		print "$before_close\)$after_close\n";

		#/* ()の中にあるセミコロンに対する改行をキャンセルする */
		$before_close =~ s/\;\n/\;/g;

#		print "$before_bracket$before_close\)\n $after_close\n--------------------------------------\n";
		$local_line = "$before_bracket$before_close\)\n $after_close";

		#/* else ifの場合の改行をキャンセル */
		if ($word eq "if")
		{
#			print "before----------------------------------------------------------------\n";
#			print "$local_line";
			while ($local_line =~ /else\s*\n\s*if/)
			{
				$local_line =~ s/else\s*\n\s*if/else if/g;
			}
#			print "after-----------------------------------------------------------------\n";
#			print "$local_line";
		}
	}

	#/* スペースと改行だけの行をまとめて削除する */
	my @split_lines = split(/\n/, $local_line);
	my $split_line;

	$local_line = "";
	foreach $split_line (@split_lines)
	{
		$split_line = $split_line . "\n";
		$split_line =~ s/^\s*\n/ /;                   #/* スペースと改行だけの行は削除       */
		$local_line = $local_line . $split_line;
	}

	&output_line($local_line);
}


#/* 四則演算の計算 */
sub calc_text
{
	my $text = $_[0];
	my $result = 0;
	my $index_close = -1;
	my $index_open = 0;
	my $temp = -1;

#	print "calc $text\n";
	
	#/* definedの処理 */
	while ($text =~ /defined[\s\(]+([_A-Za-z][_A-Za-z0-9]*)[\s\)]+/)
	{
		$result = is_valid_macro($1);
		if ($result == 1)
		{
#			print "defined $1\n";
			$text =~ s/defined[\s\(]+([_A-Za-z][_A-Za-z0-9]*)[\s\)]+/1/;
		}
		else
		{
#			print "not defined $1\n";
			$text =~ s/defined[\s\(]+([_A-Za-z][_A-Za-z0-9]*)[\s\)]+/0/;
		}
	}

	#/* ここでマクロの置き換えを実施 */
	$text = replace_macro($text, 0);
#	print "calc2 $text\n";

	while ($text =~ /0x([0-9a-fA-F]+)/)
	{
		my $hex_val = $1;
		my $value = hex $hex_val;
#		printf("HEX value : 0x%s, DEC value : %d\n", $hex_val, $value);
		
		$text =~ s/0x[0-9a-fA-F]+/$value/;
#		printf("$text\n");
	}

	$text = " " . $text;
	while ($text =~ / 0([0-9a-fA-F]+)/)
	{
		my $oct_val = $1;
		my $value = oct $oct_val;
#		printf("OCT value : 0x%s, DEC value : %d\n", $oct_val, $value);
		
		$text =~ s/0[0-9a-fA-F]+/$value/;
#		printf("$text\n");
	}

	#/* 数値に変換されなかったマクロは偽として扱う */
	$text =~ s/[A-Za-z_][0-9A-Za-z_]*/0/g;


	#/* ()の処理 */
	while (($index_close = index($text, "\)")) != -1)
	{
		#/* ()が閉じている箇所を先頭から処理していく */
#		print "index close = $index_close\n";
		$index_open = 0;

		#/* ()が開いている箇所を探す */
		while (($temp = index(substr($text, $index_open), "\(")) != -1)
		{
			if ($temp > $index_close)
			{
				last;
			}

			$index_open += ($temp + 1);
		}
#		print "index open = $index_open\n";

		$result = calc_text(substr($text, $index_open, $index_close - $index_open ));
#		print "text = $text\nresult = $result\nopen:$index_open\nclose:$index_close\n";
		substr($text, $index_open - 1, $index_close - $index_open + 2, "$result");
#		print "re calc $text\n";
	}

	#/* !の処理 */
	while ($text =~ /[\!]([0-9]+)/)
	{
		if ($1 == 0)
		{
			$result = 1;
		}
		else
		{
			$result = 0;
		}

		$text =~ s/[\!][0-9]+/$result/;
#		print "re calc $text\n";
	}

	#/* 乗算の処理 */
	while ($text =~ /([\+\-]?[0-9]+)\s*\*\s*([\+\-]?[0-9]+)/)
	{
		$result = $1 * $2;
		$text =~ s/([\+\-]?[0-9]+)\s*\*\s*([\+\-]?[0-9]+)/$result/;
#		print "re calc $text\n";
	}

	#/* 除算の処理 */
	while ($text =~ /([\+\-]?[0-9]+)\s*\/\s*([\+\-]?[0-9]+)/)
	{
		$result = $1 / $2;
		$text =~ s/([\+\-]?[0-9]+)\s*\/\s*([\+\-]?[0-9]+)/$result/;
#		print "re calc $text\n";
	}

	#/* 単項の+-を処理 */
#	print "+- reduce0 : $text\n";
	$text =~ s/\+\s+\+/ \+/g;
#	print "+- reduce1 : $text\n";
	$text =~ s/\+\s*\-/ \-/g;
#	print "+- reduce2 : $text\n";
	$text =~ s/\-\s*\+/ \-/g;
#	print "+- reduce3 : $text\n";
	$text =~ s/\-\s+\-/ \+/g;
#	print "+- reduce4 : $text\n";

	#/* 加算の処理 */
	while ($text =~ /([\+\-]?[0-9]+)\s*\+\s*([0-9]+)/)
	{
		$result = $1 + $2;
		$text =~ s/([\+\-]?[0-9]+)\s*\+\s*([0-9]+)/$result/;
#		print "re calc $text\n";
	}

	#/* 減算の処理 */
	while ($text =~ /([\+\-]?[0-9]+)\s*\-\s*([0-9]+)/)
	{
		$result = $1 - $2;
		$text =~ s/([\+\-]?[0-9]+)\s*\-\s*([0-9]+)/$result/;
#		print "re calc $text\n";
	}

	#/* <比較の処理 */
	while ($text =~ /([\+\-]?[0-9]+)\s*<\s*([\+\-]?[0-9]+)/)
	{
		if ($1 < $2)
		{
			$result = 1;
		}
		else
		{
			$result = 0;
		}

		$text =~ s/([\+\-]?[0-9]+)\s*<\s*([\+\-]?[0-9]+)/$result/;
#		print "re calc $text\n";
	}


	#/* >比較の処理 */
	while ($text =~ /([\+\-]?[0-9]+)\s*>\s*([\+\-]?[0-9]+)/)
	{
		if ($1 > $2)
		{
			$result = 1;
		}
		else
		{
			$result = 0;
		}

		$text =~ s/([\+\-]?[0-9]+)\s*>\s*([\+\-]?[0-9]+)/$result/;
#		print "re calc $text\n";
	}

	#/* <=比較の処理 */
	while ($text =~ /([\+\-]?[0-9]+)\s*<=\s*([\+\-]?[0-9]+)/)
	{
		if ($1 <= $2)
		{
			$result = 1;
		}
		else
		{
			$result = 0;
		}

		$text =~ s/([\+\-]?[0-9]+)\s*<=\s*([\+\-]?[0-9]+)/$result/;
#		print "re calc $text\n";
	}


	#/* >=比較の処理 */
	while ($text =~ /([\+\-]?[0-9]+)\s*>=\s*([\+\-]?[0-9]+)/)
	{
		if ($1 >= $2)
		{
			$result = 1;
		}
		else
		{
			$result = 0;
		}

		$text =~ s/([\+\-]?[0-9]+)\s*>=\s*([\+\-]?[0-9]+)/$result/;
#		print "re calc $text\n";
	}

	#/* ==比較の処理 */
	while ($text =~ /([\+\-]?[0-9]+)\s*==\s*([\+\-]?[0-9]+)/)
	{
		if ($1 == $2)
		{
			$result = 1;
		}
		else
		{
			$result = 0;
		}

		$text =~ s/([\+\-]?[0-9]+)\s*==\s*([\+\-]?[0-9]+)/$result/;
#		print "re calc $text\n";
	}

	#/* !=比較の処理 */
	while ($text =~ /([\+\-]?[0-9]+)\s*!=\s*([\+\-]?[0-9]+)/)
	{
		if ($1 != $2)
		{
			$result = 1;
		}
		else
		{
			$result = 0;
		}

		$text =~ s/([\+\-]?[0-9]+)\s*!=\s*([\+\-]?[0-9]+)/$result/;
#		print "re calc $text\n";
	}

	#/* 論理積&&の処理 */
	while ($text =~ /([\+\-]?[0-9]+)\s*\&\&\s*([\+\-]?[0-9]+)/)
	{
		if ($1 && $2)
		{
			$result = 1;
		}
		else
		{
			$result = 0;
		}

		$text =~ s/([\+\-]?[0-9]+)\s*\&\&\s*([\+\-]?[0-9]+)/$result/;
#		print "re calc $text\n";
	}

	#/* 論理和||の処理 */
	while ($text =~ /([\+\-]?[0-9]+)\s*\|\|\s*([\+\-]?[0-9]+)/)
	{
		if ($1 || $2)
		{
			$result = 1;
		}
		else
		{
			$result = 0;
		}

		$text =~ s/([\+\-]?[0-9]+)\s*\|\|\s*([\+\-]?[0-9]+)/$result/;
#		print "re calc $text\n";
	}

	$text =~ s/\s+//g;
#	print "ans == $text\n";
	return $text;
}


#/* ifdef等で現在のテキストが有効かどうか */
sub is_valid_now
{
	my $loop;
	for ($loop = 0; $loop <= $nest_level; $loop++)
	{
		if ($valid_line[$loop] == 0)
		{
			return 0;
		}
	}
	
	return 1;
}

#/* コードの有効／無効の切り替え */
sub turn_valid
{
	if ($valid_line[$nest_level] == 1)
	{
		$valid_line[$nest_level] = 0;
	}
	else
	{
		if ($once_valid[$nest_level] == 1)
		{
			$valid_line[$nest_level] = 0;
		}
		else
		{
			$valid_line[$nest_level] = 1;
			$once_valid[$nest_level] = 1;
		}
	}
}

sub push_valid_nest
{
	$nest_level++;
	push (@valid_line, $_[0]);
	push (@once_valid, $_[0]);
#	print "push_valid_nest : $nest_level, $_[0]\n";
}

sub pop_valid_nest
{
	$nest_level--;
	pop (@valid_line);
	pop (@once_valid);
#	print "pop_valid_nest:$nest_level\n";
}


#/* Cモジュール解析処理 */
sub analyze_module
{
	my $local_line = $_[0];

	if ($global_data->in_function == 1)
	{
		#/* 関数内の行数をカウント */
		$current_function->lines($current_function->lines + 1);
		$current_path->lines($current_path->lines + 1);
	}

	#/* 空行 */
	if ($local_line eq "\n")
	{
		$first_comment    = "";
		$current_comment  = "";
		$current_comments = "";
	}

	#/* コメント行 */
	if ($local_line =~ /^\/\*(.*)\*\/\n/)
	{
		my $temp_comment;
#		print "comment line $1\n";
		$current_comments = $current_comment . $1;

		$temp_comment = $1;
		if ($temp_comment =~ /[^\s\*\-\_\=\@\~\!]/)
		{
			#/* スペースと記号だけのコメント行は無視する */
			if ($current_comment eq "")
			{
				$first_comment = $temp_comment;
			}
			$current_comment = $temp_comment;
#			print "current_comment2 : $current_comment\n";
		}

		if ($current_comment =~ /\@brief[ \t]*([^\n]+)/)
		{
#			print "find \@brief $1\n";
			$current_brief = $1;
		}

		$global_data->comment($global_data->comment+1);

		if ($global_data->in_function == 1)
		{
			#/* 関数内のコメント行数をカウント */
			$current_function->comment($current_function->comment + 1);
			$current_path->comment($current_path->comment + 1);
		}
		return;
	}

	#/* インクルードファイルを列挙 */
	if ($local_line =~ /\#include\s*[\"\<](.*)[\"\>]/)
	{
		my $path = $1;
		while ($path =~ /[\/\\]/)
		{
			$path =~ s/.*[\/\\]([^\n]*)/$1/;
		}

		print "include $path\n";
		push @include_files, $path;
		return;
	}

	if ($local_line =~ /\#include\s*__C_ANALYZE_LITERALS_([0-9]+)/)
	{
		my $path = $literals[$1];
		$path =~ s/\"//g;
		while ($path =~ /[\/\\]/)
		{
			$path =~ s/.*[\/\\]([^\n]*)/$1/;
		}

		print "include $path\n";
		push @include_files, $path;
		return;
	}

	#/* インクルードとプラグマ以外のディレクティブは無視 */
	if ($local_line =~ /^\#/)
	{
#		print "ignore directive \#$'\n";
		return;
	}

	#/* 新しい構文が開始した場合は、まず原文を保持 */
	$current_sentence->text($current_sentence->text . $local_line);

	&analyze_line($local_line);
	if ($global_data->in_function == 1)
	{
		&analyze_function_line();
	}
	else
	{
		&analyze_global_line();
	}
}


#/* 1行解析処理 */
sub analyze_line
{
	my $local_line = $_[0];
	my $current_pos = 0;
	my $remaining_line;
	my $sentence;

#	print "------------------------\n";
#	print "$local_line";
#	print "------------------------\n";
	while (substr($local_line, $current_pos) =~ /[^\n]/ )
	{
		$remaining_line = substr($local_line, $current_pos);

		if ($remaining_line =~ /^(\s+)/)
		{
			#/* スペースはスキップ */
			$current_pos += length($1);
		}
		elsif ($remaining_line =~ /^([_A-Za-z][_A-Za-z0-9]*)/)
		{
			#/* シンボルもしくは予約語 */
			$sentence = $1;
#			print "sentence \[$1\]\n";
			&push_current_word($sentence);
			if ($1 =~ /^static$/)
			{
				$current_sentence->static(1);
			}
			elsif ($1 =~ /^const$/)
			{
				$current_sentence->const(1);
			}
			elsif ($1 =~ /^extern$/)
			{
				$current_sentence->extern(1);
			}
			elsif ($1 =~ /^(struct|union|enum)$/)
			{
#				print "$1\n";
				$current_sentence->struct(1);
			}
			elsif ($1 =~ /^(inline|volatile|auto|signed)$/)
			{
				#/* 解析対象外 */
#				print "$1\n";
			}
			elsif ($1 =~ /^unsigned$/)
			{
				$current_sentence->unsigned(1);
			}
			elsif ($1 =~ /^(void|char|int|short|long|float|double)$/)
			{
#				print "$1\n";
			}
			elsif ($1 =~ /^(if|for|else|while|do|switch|case|break|continue|return|goto)$/)
			{
				#/* 制御文。これらは{};:の文の区切りまでに一つしか入らないはず */
#				print "$1\n";
			}
			elsif ($1 =~ /^sizeof$/)
			{
#				print "$1\n";
			}
			else
			{
#				print "$sentence\n";
				if ($global_data->in_function == 1)
				{
					
				}
				else
				{
					if ($current_pos == 0)
					{
						#/* 先頭にいきなり未知の語がくる場合 */
					}
				}
			}

			$current_pos += length($sentence);
		}
		elsif ($remaining_line =~ /^([\+\-]*[0-9]+\.[0-9]*[eE][\+\-]*[0-9]+[fFlL]*)/)
		{
			#/* 浮動小数 */
			#/*（C99では16進表記も可能だそうですが、ここでは無視 */
#			print "float1 $1 from $remaining_line";
			&push_current_word($1);
			$current_pos += length($1);
		}
		elsif ($remaining_line =~ /^([\+\-]*[0-9]*\.[0-9]+[eE][\+\-]*[0-9]+[fFlL]*)/)
		{
			#/* 浮動小数 */
#			print "float2 $1 from $remaining_line";
			&push_current_word($1);
			$current_pos += length($1);
		}
		elsif ($remaining_line =~ /^([\+\-]*[0-9]+\.[0-9]*[fFlL]*)/)
		{
			#/* 浮動小数 */
#			print "float3 $1 from $remaining_line";
			&push_current_word($1);
			$current_pos += length($1);
		}
		elsif ($remaining_line =~ /^([\+\-]*[0-9]*\.[0-9]+[fFlL]*)/)
		{
			#/* 浮動小数 */
#			print "float4 $1 from $remaining_line";
			&push_current_word($1);
			$current_pos += length($1);
		}
		elsif ($remaining_line =~ /^([\+\-]*[0-9]+[eE][\+\-]*[0-9]+[fFlL]*)/)
		{
			#/* 浮動小数 */
#			print "float5 $1 from $remaining_line";
			&push_current_word($1);
			$current_pos += length($1);
		}
		elsif ($remaining_line =~ /^(0[xX][0-9a-fA-F]+[uUlL]*)/)
		{
			#/* 16進数 */
#			print "$1\n";
			&push_current_word($1);
			$current_pos += length($1);
		}
		elsif ($remaining_line =~ /^(0[0-7]*[uUlL]*)/)
		{
			#/* 8進数 */
#			print "$1\n";
			&push_current_word($1);
			$current_pos += length($1);
		}
		elsif ($remaining_line =~ /^([1-9][0-9]*[uUlL]*)/)
		{
			#/* 10進数 */
#			print "$1\n";
			&push_current_word($1);
			$current_pos += length($1);
		}
		elsif ($remaining_line =~ /^('\\*.?')/)
		{
			#/* 文字定数 */
#			print "$1\n";
			&push_current_word($1);
			$current_pos += length($1);
		}
		elsif ($remaining_line =~ /(^\;)/)
		{
			#/* セミコロン */
#			print "$1\n";
			$current_pos += length($1);
			&push_current_word($1);
#			&disp_current_words();
#			&clear_current_sentence();
		}
		elsif ($remaining_line =~ /^([\:\?\,]+)/)
		{
			#/* 構文上の記号 */
#			print "$1\n";
			&push_current_word($1);
			$current_pos += length($1);
		}
		elsif ($remaining_line =~ /^(\.|\-\>)/)
		{
			#/* 構造体へのアクセス（.は浮動小数か構造体アクセスか） */
			&push_current_word($1);
			$current_pos += length($1);
		}
		elsif ($remaining_line =~ /^(\<\<\=|\>\>\=)/)
		{
			#/* シフト＋代入 */
#			print "operator three char! $1\n";
			&push_current_word($1);
			$current_pos += length($1);
		}
		elsif ($remaining_line =~ /^([\+\-\*\/\%\&\|\^]\=)/)
		{
			#/* 演算＋代入 */
#			print "operator two char1! $1\n";
			&push_current_word($1);
			$current_pos += length($1);
		}
		elsif ($remaining_line =~ /^(\=\=|\!\=|\<\=|\>\=|\<\<|\>\>|\&\&|\|\|)/)
		{
			#/* 二文字の演算子 */
#			print "operator two char2! $1\n";
			&push_current_word($1);
			$current_pos += length($1);
		}
		elsif ($remaining_line =~ /^(\+\+|\-\-|\!|\~|\&|\*)/)
		{
			#/* 単項演算子 */
#			print "Unary operator! $1\n";
			&push_current_word($1);
			$current_pos += length($1);
		}
		elsif ($remaining_line =~ /^([\+\-\*\/\%\=\<\>\&\|\^])/)
		{
			#/* 一文字の演算子 */
#			print "operator one char! $1\n";
			&push_current_word($1);
			$current_pos += length($1);
		}
		elsif ($remaining_line =~ /^[\"]/)
		{
			#/* ダブルクォーテーション、\などリテラルにのみ出る文字 */
			$current_pos++;
			die "double quatation appeared!\n";
		}
		elsif ($remaining_line =~ /^(\\[abnrftv\\\?\"\'0])/)
		{
			#/* エスケープ文字 */
#			print "$1\n";
			$current_pos += length($1);
			die "escape sequence!\n";
		}
		elsif ($remaining_line =~ /^(\[)/)
		{
			#/* [ 開く */
			&push_current_word($1);
			$current_pos++;
		}
		elsif ($remaining_line =~ /^(\])/)
		{
			#/* ] 閉じる */
			&push_current_word($1);
			$current_pos++;
		}
		elsif ($remaining_line =~ /^(\()/)
		{
			#/* ( 開く */
			&push_current_word($1);
			$current_pos++;
		}
		elsif ($remaining_line =~ /^(\))/)
		{
			#/* ) 閉じる */
			&push_current_word($1);
			$current_pos++;
		}
		elsif ($remaining_line =~ /^(\{)/)
		{
			#/* { 開く */
			&push_current_word($1);
			$current_pos++;
		}
		elsif ($remaining_line =~ /^(\})/)
		{
			#/* } 閉じる */
			&push_current_word($1);
			$current_pos++;
		}
		else
		{
			$current_pos++;
			die "unknown word! $remaining_line\n";
		}
	}
}


#/* 解析中の構文のクリア */
sub clear_current_sentence
{
	my $text;
#	print "-------------- clear --------------\n";
	$current_sentence->text("");
	$current_sentence->name("");
	$current_sentence->typ("");
	$current_sentence->typ_fixed(0);
	$current_sentence->name_fixed(0);
	$current_sentence->init_val("");
	$current_sentence->typedef(0);
	$current_sentence->struct(0);
	$current_sentence->extern(0);
	$current_sentence->static(0);
	$current_sentence->const(0);
	$current_sentence->unsigned(0);
	$current_sentence->position(0);
	$current_sentence->astarisk(0);
	$current_sentence->astarisk_f(0);
	$current_sentence->astarisk_u(0);
	$current_sentence->arg_list("");
	$current_sentence->is_func(0);

	$current_sentence->clear(0);
	$current_sentence->backward("");
	$current_sentence->switch_val("");
	$current_sentence->pu_text("");
	$current_sentence->case_val("");
	$current_sentence->func_call(0);
	$current_sentence->case_cond("");

	@{$current_sentence->words} = ();
#	&disp_current_words();
}


sub push_current_word
{
	my $word = $_[0];
#	print "-------------- push $word --------------\n";
	push @{$current_sentence->words}, $word;
}


sub disp_current_words
{
	my $word;
	my @local_array = @{$current_sentence->words};
	my $text = $current_sentence->text;

	print "-------------- disp --------------\n";
	print "$text";
	foreach $word (@local_array)
	{
		print "$word\n";
	}
	print "-------------- disp end ----------\n";
}


#/* テキストに単語を付け足す。二語目以降の場合は、スペースを空ける */
sub add_word_to_text
{
	my $text = $_[0];
	my $word = $_[1];

	if ($text eq "")
	{
		$text = $word;
	}
	else
	{
		$text = $text . " " . $word;
	}

	return $text;
}


#/* まず最初のワードを決定する */	
sub analyze_global_first_word
{
	my $temp_text = "";
	my $loop = $_[0];
	my @local_array = @{$current_sentence->words};

	for (    ; $loop < @local_array; $loop++)
	{
		if ($local_array[$loop] eq "typedef")
		{
			#/* typedefはとりあえず覚えておく */
			$current_sentence->typedef(1);
		}
		elsif ($local_array[$loop] =~/^(struct|union|enum)$/)
		{
			$current_sentence->typ(&add_word_to_text($current_sentence->typ, $1));
			if ($loop + 1 == @local_array)
			{
				#/* 末尾だったら持ち越し */
				return $loop;
			}

			if ($local_array[$loop + 1] =~ /([_A-Za-z][_A-Za-z0-9]*)/)
			{
				#/* 構造体などのタグ名はここで処理する（まだ型は確定していない） */
				$current_sentence->typ(&add_word_to_text($current_sentence->typ, $1));
				$loop++;

				if ($loop + 1 == @local_array)
				{
					#/* 末尾だったらさらに持ち越し */
					return $loop;
				}

				if ($local_array[$loop + 1] ne "{")
				{
					#/* 構造体の定義が始まらないようであれば、型を確定する */
					$current_sentence->typ_fixed(1);
				}
			}
		}
		elsif ($local_array[$loop] =~ /^(void|char|int|short|long|float|double)$/)
		{
			#/* 標準の型 */
			$current_sentence->typ(&add_word_to_text($current_sentence->typ, $1));
			$current_sentence->typ_fixed(1);
		}
		elsif ($local_array[$loop] =~ /^(unsigned|signed)$/)
		{
			#/* unsigned, signedの後ろのintは省略可 */
			$current_sentence->typ(&add_word_to_text($current_sentence->typ, $1));
			$current_sentence->typ_fixed(1);
		}
		elsif ($local_array[$loop] =~ /^(static|extern|inline|const|volatile|auto)$/)
		{
			#/* 型の修飾子 */
#			$current_sentence->typ(&add_word_to_text($current_sentence->typ, $1));
		}
		elsif ($local_array[$loop] eq "(")
		{
			#/* 丸括弧は型の終了(関数、関数ポインタの場合は、引数リストも含めて型になるが、ひとまずここでは終了) */
			($current_sentence->typ_fixed) or die "strange sentence1-1 may be omitted type! $loop, @local_array\n";		#/* 型の省略は不許可 */
			last;
		}
		elsif ($local_array[$loop] eq "*")
		{
			#/* アスタリスクの場合は、型定義は完了 */
			($current_sentence->typ_fixed) or die "strange sentence1-2 may be omitted type! $loop, @local_array\n";		#/* 型の省略は不許可 */
			last;
		}
		elsif ($local_array[$loop] eq "=")
		{
			#/* イコールが来た場合は、型定義は完了 */
			($current_sentence->typ_fixed) or die "strange sentence1-3 may be omitted type! $loop, @local_array\n";		#/* 型の省略は不許可 */
			last;
		}
		elsif ($local_array[$loop] eq "[")
		{
			#/* 配列の場合 */
			die "strange array define! may be omitted type!\n";
		}
		elsif ($local_array[$loop] eq "{")
		{
			$loop = &analyze_some_bracket($loop, \$temp_text);
			if ($temp_text eq "")
			{
				#/* 空文だったら、次行に持ち越して処理継続する */
				return $loop;
			}

			#/* 型の定義は完了 */
#			printf "temp text : $temp_text\n";
			$current_sentence->typ(&add_word_to_text($current_sentence->typ, $temp_text));
			$current_sentence->typ_fixed(1);
			$loop++;
			last;
		}
		elsif ($local_array[$loop] =~ /([_A-Za-z][_A-Za-z0-9]*)/)
		{
			#/* シンボル */
			if ($current_sentence->typ_fixed)
			{
				last;
			}

			#/* ToDo マクロで修飾子とかを作られた時の対処 */

			$current_sentence->typ(&add_word_to_text($current_sentence->typ, $1));
			$current_sentence->typ_fixed(1);
		}
		elsif ($local_array[$loop] eq ";")
		{
			if ($loop == 0)
			{
				#/* 無意味な ; */
#				print "; without sentence!\n";
			}
			else
			{
				#/* 型だけで文が閉じているケース。 */
				($current_sentence->typ_fixed == 1) or die die "strange sentence1-4 may be omitted type! $loop, @local_array\n";
			}
		}
		else
		{
			die "strange sentence1-5 may be omitted type! $loop, @local_array\n";
		}
	}

	return $loop;
}


sub analyze_global_round_bracket
{
	my $loop = $_[0];
	my $ref_text = $_[1];
	my $out_text = "";
	my $sub_text = "";
	my @local_array = @{$current_sentence->words};
	my $local_astarisk = 0;
	my $arglist_in_this_level = 0;

#	print "analyze_global_round_bracket $loop, @local_array\n";
	($local_array[$loop] eq "(") or die "not roud bracket open!\n";
	$out_text = "(";
	$loop++;
	for (    ; $loop < @local_array; $loop++)
	{
		if ($local_array[$loop] eq "(")
		{
			#/* ()を見つけたら */
			if ($current_sentence->name_fixed)
			{
				#/* すでにシンボル名は決定しているので、引数リストがくる。ここでは再帰しない */
				$loop = &analyze_some_bracket($loop, \$sub_text);
				if ($sub_text eq "")
				{
					return $loop;
				}

#				printf "() found! $sub_text is_func:%d\n", $current_sentence->is_func;

				if ($current_sentence->is_func)
				{
					#/* すでに引数リストが出て、関数が確定しているのに、さらに()括弧が来るのは、関数ポインタを戻り値とする関数か、もしくはその関数へのポインタ */
					if ($current_sentence->astarisk_f > 0)
					{
						#/* 関数ポインタの場合 */
#						printf "astarisk_f : %d\n", $current_sentence->astarisk_f;
						$current_sentence->typ($current_sentence->typ . " (" . "*" x $current_sentence->astarisk . ") " . $sub_text . " (" . "*" x $current_sentence->astarisk_f . ") " . $current_sentence->arg_list);
					}
					else
					{
						#/* 関数の場合 */
#						printf "no astarisk_f : %d\n", $current_sentence->astarisk_f;
						$current_sentence->typ($current_sentence->typ . "*" x $current_sentence->astarisk . " (" . "*" x $current_sentence->astarisk_u . ") " . $sub_text);
						$current_sentence->astarisk_u(0);
					}
				}
				else
				{
					#/* とりあえず関数か関数ポインタかは確定。引数リストを覚えておく */
					if ($current_sentence->astarisk_f > 0)
					{
						#/* 関数ポインタの場合 */
#						printf "astarisk_f4 : type:%s\n", $current_sentence->typ;
#						printf "astarisk_f4 : temp_text:$sub_text\n";
						$current_sentence->typ($current_sentence->typ . "*" x $current_sentence->astarisk . " (" . "*" x $current_sentence->astarisk_f . ") ");
					}

					$current_sentence->arg_list($sub_text);
					$current_sentence->is_func(1);
					$arglist_in_this_level = 1;
				}
			}
			else
			{
				$loop = &analyze_global_round_bracket($loop, \$sub_text);
				if ($sub_text eq "")
				{
					$$ref_text = "";
					return $loop;
				}

				$out_text = &add_word_to_text($out_text, $sub_text);
			}
		}
		elsif ($local_array[$loop] eq ")")
		{
			#/* 閉じたところで終了。 */
			($current_sentence->name_fixed) or die "missing token! @local_array\n";

			if ($current_sentence->is_func == 0)
			{
				#/* 括弧が閉じる際に、引数リストが存在しておらず、なおかつローカルアスタリスクがある場合は、関数ポインタになる可能性あり */
				$current_sentence->astarisk_f($current_sentence->astarisk_f + $local_astarisk);
#				printf "add astarisk_f : %d $loop, @local_array\n", $current_sentence->astarisk_f;
			}
			else
			{
				if ($arglist_in_this_level)
				{
					#/* この()の中に引数リストがあった場合、アスタリスクの扱いはまだ判断できない */
					$current_sentence->astarisk_u($current_sentence->astarisk_u + $local_astarisk);
#					printf "add astarisk_u : %d $loop, @local_array\n", $current_sentence->astarisk_u;
				}
				else
				{
					#/* すでに引数リストがある場合は、このローカルアスタリスクは戻り値の型にかかる */
					$current_sentence->astarisk($current_sentence->astarisk + $local_astarisk);
				}
			}

			$out_text = &add_word_to_text($out_text, $local_array[$loop]);
			$$ref_text = $out_text;
			return $loop;
		}
		elsif ($local_array[$loop] eq "*")
		{
			#/* ()内のアスタリスクは位置によって型につくのか、関数ポインタになるのか分かれる */
			$local_astarisk++;
			$out_text = &add_word_to_text($out_text, $local_array[$loop]);
		}
		elsif ($local_array[$loop] =~ /^(void|char|int|short|long|float|double)$/)
		{
			#/* 既存の型が来た場合は、戻り値の型を省略した関数の宣言ということになるが、不許可！ */
			die "omitted return type is forbidden! case 1  $loop, @local_array\n";
		}
		elsif ($local_array[$loop] eq ",")
		{
			#/* , が入るということは引数リストということ。これも戻り値の型を省略したとみなして不許可！ */
			die "omitted return type is forbidden! case 2  $loop, @local_array\n";
		}
		elsif ($local_array[$loop] =~ /([_A-Za-z][_A-Za-z0-9]*)/)
		{
			#/* シンボル名が来た！ */
			$current_sentence->name($1);
			$current_sentence->name_fixed(1);
			$out_text = &add_word_to_text($out_text, $local_array[$loop]);
		}
		else
		{
			#/* その他のワード。あり得ない */
			die "strange global round bracket! @local_array\n";
		}
	}

	#/* ループを抜けた場合は、()が閉じていないので次行に持ち越し */
	$$ref_text = "";
	return $_[0];
}

#/* 続いてシンボルを確定する */
sub analyze_global_second_word
{
	my $loop = $_[0];
	my $temp_text = "";
	my @local_array = @{$current_sentence->words};

#	print "analyze_global_second_word! $loop, @local_array\n";
	for (    ; $loop < @local_array; $loop++)
	{
		if ($local_array[$loop] eq "(")
		{
			#/* ()を見つけたら */
			if ($current_sentence->name_fixed)
			{
				#/* すでにシンボル名は決定しているので、引数リストがくる。ここでは再帰しない */
				$loop = &analyze_some_bracket($loop, \$temp_text);
#				printf "() found2! $temp_text is_func:%d\n", $current_sentence->is_func;
				if ($temp_text eq "")
				{
#					print "return $loop;\n";
					return $loop;
				}

				if ($current_sentence->is_func)
				{
					#/* すでに引数リストが出て、関数が確定しているのに、さらに()括弧が来るのは、関数ポインタを戻り値とする関数か、もしくはその関数へのポインタ */
					if ($current_sentence->astarisk_f > 0)
					{
						#/* 関数ポインタの場合 */
#						printf "astarisk_f2 : %d\n", $current_sentence->astarisk_f;
						$current_sentence->typ($current_sentence->typ . "*" x $current_sentence->astarisk . $temp_text . " (" . "*" x $current_sentence->astarisk_f . ") " . $current_sentence->arg_list);
#						printf "astarisk_f2 : type:%s\n", $current_sentence->typ;
#						printf "astarisk_f2 : temp_text:$temp_text\n";
#						printf "astarisk_f2 : arg_list:%s\n", $current_sentence->arg_list;
					}
					else
					{
						#/* 関数の場合 */
#						printf "no astarisk_f2 : %d\n", $current_sentence->astarisk_f;
						$current_sentence->typ($current_sentence->typ . "*" x $current_sentence->astarisk . " (" . "*" x $current_sentence->astarisk_u . ") " . $temp_text);
						$current_sentence->astarisk_u(0);
#						printf "no astarisk_f2 : type:%s, temp_text:$temp_text\n", $current_sentence->typ;
					}
				}
				else
				{
					#/* とりあえず関数か関数ポインタかは確定。引数リストを覚えておく */
					if ($current_sentence->astarisk_f > 0)
					{
						#/* 関数ポインタの場合 */
						$current_sentence->typ($current_sentence->typ . "*" x $current_sentence->astarisk . " (" . "*" x $current_sentence->astarisk_f . ") " . $temp_text);
#						printf "astarisk_f3 : type:%s\n", $current_sentence->typ;
#						printf "astarisk_f3 : temp_text:$temp_text\n";
					}

					$current_sentence->arg_list($temp_text);
					$current_sentence->is_func(1);
				}
			}
			else
			{
				#/* 名前が確定していない場合は、専用の解析処理 */
				$loop = &analyze_global_round_bracket($loop, \$temp_text);
			}
		}
		elsif ($local_array[$loop] =~ /([_A-Za-z][_A-Za-z0-9]*)/)
		{
			#/* シンボル名が来た！ */
			$current_sentence->name($1);
			$current_sentence->name_fixed(1);
		}
		elsif ($local_array[$loop] eq "*")
		{
			$current_sentence->astarisk($current_sentence->astarisk + 1);
		}
		elsif ($local_array[$loop] eq "{")
		{
			#/* ここでは何もしない */
		}
		elsif ($local_array[$loop] eq "[")
		{
			#/* 配列の場合 */
			($current_sentence->name_fixed) or die "strange array define! $loop, @local_array\n";
			$loop = &analyze_some_bracket($loop, \$temp_text);
			$current_sentence->name($current_sentence->name . $temp_text);
		}
		elsif ($local_array[$loop] eq "=")
		{
			#/* 変数の初期値が来るパターン */
			($current_sentence->name_fixed) or die "strange init value! $loop, @local_array\n";

			$loop++;
			while ($loop < @local_array) 
			{
				if ($local_array[$loop] eq "{")
				{
					$loop = &analyze_some_bracket($loop, \$temp_text);
					if ($temp_text eq "")
					{
						#/* 空文だったら、次行に持ち越して = から処理継続する */
						return $loop - 1;
					}

					$current_sentence->init_val(&add_word_to_text($current_sentence->init_val, $temp_text));
				}
				elsif ($local_array[$loop] eq "(")
				{
					$loop = &analyze_some_bracket($loop, \$temp_text);
					if ($temp_text eq "")
					{
						#/* 空文だったら、次行に持ち越して = から処理継続する */
						return $loop - 1;
					}

					$current_sentence->init_val(&add_word_to_text($current_sentence->init_val, $temp_text));
				}
				elsif ($local_array[$loop] eq ",")
				{
					$loop--;
					last;
				}
				elsif ($local_array[$loop] eq ";")
				{
					$loop--;
					last;
				}
				else
				{
					$current_sentence->init_val(&add_word_to_text($current_sentence->init_val, $local_array[$loop]));
				}
				
				$loop++;
			}
		}
		elsif ($local_array[$loop] eq ",")
		{
			($current_sentence->name_fixed) or die "strange comma without symbol! $loop, @local_array\n";
			if (($current_sentence->is_func == 0) ||
			    ($current_sentence->astarisk_f > 0))
			{
				if ($current_sentence->astarisk_f > 0)
				{
					$current_sentence->astarisk($current_sentence->astarisk_f);
					$current_sentence->astarisk_f(0);
				}
				printf "add variable with ,   name : %s, astarisk_f : %d, astarisk : %d\n", $current_sentence->name, $current_sentence->astarisk_f, $current_sentence->astarisk;
				&add_variable();
			}
			else
			{
				#/* 関数の宣言の場合は、無視 */
				$current_sentence->is_func(0);
			}

			#/* 型以外の情報は忘れる */
			$current_sentence->name("");
			$current_sentence->name_fixed(0);
			$current_sentence->init_val("");
			$current_sentence->astarisk(0);
			$current_sentence->astarisk_f(0);
			$current_sentence->astarisk_u(0);
			$current_sentence->arg_list("");
		}
		elsif ($local_array[$loop] eq ";")
		{
			#/* ここでは何もしない */
		}
		else
		{
			die "strange sentence! $loop, @local_array\n";
		}
	}

#	print "return $loop;\n";
	return $loop;
}

sub analyze_global_sentence
{
	my $loop = $current_sentence->position;
	my @local_array = @{$current_sentence->words};

	my $temp_text;

#	print "analyze_global_sentence : $loop, @local_array\n";

	#/* まず最初に型を決定する */	
	if ($current_sentence->typ_fixed == 0)
	{
		$loop = &analyze_global_first_word($loop);
		if ($current_sentence->typ_fixed == 0)
		{
			#/* 型が未確定の場合は、次行に持ち越して継続 */
			return $loop;
		}
	}

	$loop = &analyze_global_second_word($loop);
	return $loop;
}

#/* グローバルスコープの１行解析 */
sub analyze_global_line
{
	my @local_array = @{$current_sentence->words};

	if (@local_array == 0)
	{
		return;
	}

	if ($local_array[@local_array - 1] eq ";")
	{
#		print "analyze_global_line ; @local_array\n";
		$current_sentence->position(&analyze_global_sentence());
		if ($current_sentence->typ_fixed == 1)
		{
			if (($current_sentence->is_func == 0) ||
				($current_sentence->astarisk_f > 0)) {
				if ($current_sentence->name_fixed) {
					&add_variable();
				}
			}

			&clear_current_sentence();
			$current_brief    = "";
			return;
		}
	}
	elsif ($local_array[@local_array - 1] eq "{")
	{
#		print "analyze_global_line { @local_array\n";
		$current_sentence->position(&analyze_global_sentence());
		if ($current_sentence->is_func == 1)
		{
			if ($current_sentence->astarisk_u)
			{
				$current_sentence->astarisk($current_sentence->astarisk + $current_sentence->astarisk_u);
			}

			&new_function($current_sentence->name, $current_sentence->typ);
			$global_data->in_function(1);
			$global_data->indent($global_data->indent + 1);
			&clear_current_sentence();
			$current_function->lines($current_function->lines + 1);
			$current_path->lines($current_path->lines + 1);
			push @{$current_function->texts}, "{\n";
			push @{$current_path->texts}, "{\n";
			return;
		} else {

		}
		
	}
	else
	{
		#/* 次行に処理を持ち越す */
#		print "analyze_global_line none @local_array\n";
	}

}


#/* 親パスに復帰させる */
sub pop_path
{
	#/* パス復帰する前に現在のpu_blockを吐き出す */
	&push_pu_text("");

	$current_path = $current_path->parent;
	pop @path_stack;
}

sub new_path
{
	my $path_type = $_[0];
	my $parent   = $_[1];
	my $indent   = $_[2];
	my $temp_path;
	my $ret_val = 0;
#	print "new_path @ $indent\n";


	$temp_path = Path->new();
	$temp_path->function($current_function);
	$temp_path->backward("");
	$temp_path->switch_val("");
	$temp_path->case_count(0);
	$temp_path->parent($parent);
	$temp_path->lines(0);
	$temp_path->type("");
	$temp_path->steps(0);
	$temp_path->comment(0);
	$temp_path->indent($indent);
	$temp_path->break(0);
	$temp_path->type($path_type);
	$temp_path->backward($current_sentence->backward);
	$temp_path->switch_val($current_sentence->switch_val);
	$temp_path->pu_block("");
	$temp_path->call_block(0);
	@{$temp_path->texts}     = ();
	@{$temp_path->pu_text}   = ();
	@{$temp_path->var_read}  = ();
	@{$temp_path->var_write} = ();
	@{$temp_path->func_call} = ();
	@{$temp_path->case_val}  = ();

	if ($parent ne "")
	{
		#/* 元のPATHの子として登録する */
		push @{$parent->child}, $temp_path;
		$ret_val = @{$parent->child} - 1;
		$temp_path->level($parent->level + 1);
	}
	else
	{
		$temp_path->level(1);
	}

	$current_path = $temp_path;
	push @path_stack, $current_path;
	return $ret_val;
}

sub new_function
{
	my $name = $_[0];
	my $typ = $_[1];
	my $astarisk = $current_sentence->astarisk;

	while ($astarisk > 0)
	{
#		print "add *!\n";
		$typ = $typ . "*";
		$astarisk--;
	}

	print "new function! [ $typ ][ $name ]\n";
	$current_function = Functions->new();
	$current_function->name($name);
	$current_function->ret_typ($typ);
	$current_function->lines(1);
	$current_function->comment(0);
	$current_function->steps(0);
	$current_function->make_tree(0);

	if ($current_brief ne "")
	{
		#/* @briefコメントがある場合は、そちらを優先(先頭の空白は取っ払う) */
		$current_brief =~ s/^\s*//;
		$current_function->summary($current_brief);
		$current_brief = "";
		$current_comment = "";
		$first_comment   = "";
	}
	else
	{
		#/* @briefコメントがない場合は、直近もしくは同一行後方のコメントを採用(先頭の空白は取っ払う) */
		$first_comment =~ s/^\s*//;
		$current_comment =~ s/^\s*//;
		$current_function->summary($first_comment);
		$current_comment = "";
		$first_comment   = "";
	}

	$current_function->static($current_sentence->static);
	@{$current_function->texts}      = ($current_sentence->text);
	@{$current_function->args_typ}   = ();
	@{$current_function->args_name}  = ();
	@{$current_function->write_args} = ();
	@{$current_function->var_read}   = ();
	@{$current_function->var_write}  = ();
	@{$current_function->func_call}  = ();
	@{$current_function->func_ref}   = ();
	@{$current_function->label}      = ();
	@{$current_function->local_val}  = ();
	%{$current_function->typedefs}   = ();

	&analyze_arg_list();

	&new_path("", "", 0);
	$current_function->path($current_path);
}



#/* 関数の仮引数解析処理(戻り値は引数リストを閉じる)のインデックス) */
sub analyze_arg_list
{
#	my @local_array = @{$current_sentence->words};
	my @local_array = split(/ /, $current_sentence->arg_list);
	my $loop = 1;
	my $temp1 = "";
	my $temp2 = "";
	my $astarisk = 0;
	my $is_struct = "";

#	printf "start analyze arg list : %s\n", $current_sentence->arg_list;
	while($loop + 1 < @local_array)
	{
#		print "analyze arg list : $local_array[$loop]\n";
		if ($local_array[$loop] =~ /[\)\,]/)
		{
			#/* , または ) で引数の区切り */

			if ($temp1 eq "")
			{
				#/* ()で引数のないパターン */
				print "function with no arg1!\n";
			}
			elsif ($temp1 eq "void")
			{
				#/* (void)で引数のないパターン */
				print "function with no arg2!\n";
			}
			elsif ($temp2 eq "")
			{
				#/* 型を省略した場合 */
				push @{$current_function->args_typ},  "int";
				push @{$current_function->args_name}, "$temp1";
				$temp2 = "";
			}
			else
			{
				$temp1 = "";
				$temp2 = "";
				$is_struct = "";
				$astarisk = 0;
			}

			if ($local_array[$loop] eq ")")
			{
				last;
			}
		}
		elsif ($local_array[$loop] =~ /(\*+)/)
		{
			if ($temp1 eq "")
			{
				die "strange arg list!\n";
			}
			else
			{
				$astarisk += length($local_array[$loop]);
			}
		}
		elsif ($local_array[$loop] =~ /^(struct|union|enum)$/)
		{
			$is_struct = "$1 ";
		}
		elsif ($temp1 eq "")
		{
			#/* 最初のシンボル */
			$temp1 = $local_array[$loop];
		}
		else
		{
			#/* 二つ目のシンボル */
			my $type_name;
			$temp2 = $local_array[$loop];
			$type_name = "$is_struct" . "$temp1";
			while ($astarisk > 0)
			{
				$type_name = $type_name . "*";
				$astarisk--;
			}

#			print "arg type : $type_name, arg name : $temp2\n";
			push @{$current_function->args_typ},  $type_name;
			push @{$current_function->args_name}, $temp2;
		}

		$loop++;
	}

	return $loop;
}


#/* 変数の登録 */
sub add_variable
{
	my $type = $current_sentence->typ;
	my $name = $current_sentence->name;
	my $astarisk = $current_sentence->astarisk;
	my $new_variable = Variables->new();

	if ($current_sentence->typedef)
	{
		print "typedef! [$name] as [$type]\n";
		if ($global_data->in_function == 1)
		{
			${$current_function->typedefs}{$name} = $type;
		}
		else
		{
			$global_typedefs{$name} = $type;
		}
	}
	else
	{
		$new_variable->name($name);
		$type = $type . "*" x $astarisk;
		$new_variable->typ($type);

		$new_variable->init_val($current_sentence->init_val);
		$new_variable->extern($current_sentence->extern);
		$new_variable->static($current_sentence->static);
		$new_variable->const($current_sentence->const);

		if ($current_brief ne "")
		{
			#/* @briefコメントがある場合は、そちらを優先(先頭の空白は取っ払う) */
			$current_brief =~ s/^\s*//;
			$new_variable->comment_txt($current_brief);
			$current_brief = "";
			$current_comment = "";
			$first_comment   = "";
		}
		else
		{
			#/* @briefコメントがない場合は、直近もしくは同一行後方のコメントを採用(先頭の空白は取っ払う) */
			$current_comment =~ s/^\s*//;
			$new_variable->comment_txt($current_comment);
			$current_comment = "";
			$first_comment   = "";
		}

		@{$new_variable->func_read}  = ();
		@{$new_variable->func_write} = ();
		$new_variable->section($global_data->section);

		printf "add Variable! [ %s ] [ %s ] = [ %s ]\n", $new_variable->typ, $current_sentence->name, $current_sentence->init_val;

		if ($global_data->in_function == 1)
		{
#			print "push local variable $name!!!\n";
			push @{$current_function->local_val}, $new_variable;
		}
		else
		{
			push @global_variables, $new_variable;
		}
	}
}


#/* 特に解析対象とならないようなワードの追加 */
sub add_free_word
{
	my $add_word = $_[0];

	$add_word =~ s/]/］/g;   #/* うまくエスケープできず、苦肉の策 */

	if ($current_path->pu_block eq "")
	{
		if ($add_word ne "\n")
		{
			$current_path->pu_block($add_word);
		}
	}
	elsif ($add_word eq "\n")
	{
		$current_path->pu_block($current_path->pu_block . "\n");
	}
	else
	{
		$current_path->pu_block($current_path->pu_block . " " . $add_word);
	}
}


#/* ( の解析                                     */
sub analyze_round_bracket_open
{
	my $loop        = $_[0];
	my @local_array = @{$current_sentence->words};
	my $symbol_name = "";

	if ($loop > 0)
	{
		$symbol_name = $local_array[$loop - 1];
	}

	if ($symbol_name =~ /([_A-Za-z][_A-Za-z0-9]*)/)
	{
		#/* 前の語がシンボルだった場合 */
		if ($symbol_name ne "sizeof")
		{
			print "function call! $symbol_name()\n";
			&add_function_call($symbol_name);
			$current_sentence->func_call(1);
			$current_path->call_block(1);
		}
	}

	#/* 解析対象外のワード */
	&add_free_word("(");
	return $loop;
}


sub analyze_if
{
	my $loop        = $_[0];
	my @local_array = @{$current_sentence->words};
	my $condition = "";

	#/* if文の処理 */
	($loop+1 < @local_array) or die "strange if sentence!\n";

	if ($local_array[$loop+1] ne "(")
	{
		#/* ifの後に()が来ない。マクロ使っているやつ */
		$loop++;
		$condition = $local_array[$loop];
	}
	else
	{
		$loop = &analyze_some_bracket($loop + 1, \$condition);
		if ($condition eq "")
		{
			#/* 空文だったら、次行に持ち越して処理継続する */
			$current_sentence->clear(0);
			$current_sentence->position($_[0]);
			return @local_array - 1;
		}

		#/* 一番外の()は取り除く */
		$condition =~ s/^\((.+)\)$/$1/;
	}


	my $cont_size = CONT_SIZE;
	$condition =~ s/\|\|/\|\|\n$cont_size/g;
	$condition =~ s/\&\&/\&\&\n$cont_size/g;
	if ($local_array[0] eq "else")
	{
		#/* else if文の場合は : 最後に追加されているであろうendifをpopしてしまう */
#		print "analyze else if!\n";
		pop @{$current_path->pu_text};
		pop @{$current_path->pu_text};
		&push_pu_text("elseif (" . CONT_SIZE . $condition . ") then (" . CONT_SIZE . "Yes)\n");
	}
	else
	{
		&push_pu_text("if (" . CONT_SIZE . $condition . ") then (" . CONT_SIZE . "Yes)\n");
	}

	&create_new_path("if");
	return $loop;
}

sub analyze_do
{
	my $loop        = $_[0];
	my @local_array = @{$current_sentence->words};

	&push_pu_text("partition \"do while loop\" {\n");
	&push_pu_text("repeat\n");
	&create_new_path("do");
	return $loop;
}

sub analyze_goto
{
	my $loop        = $_[0];
	my @local_array = @{$current_sentence->words};

	#/* goto文 */
	my $label = $local_array[$loop + 1];
	
	if ($label =~ /[^_A-Za-z0-9]/)
	{
		die "strange goto label!!! [$label]\n";
	}
	
	if ($local_array[$loop + 2] ne ";")
	{
		die "strange goto label without ;\n";
	}

	my $label_num = &add_array_no_duplicate($current_function->label ,$label);
	my $color = &get_color_text($label_num);
	&push_pu_text("$color:goto **$label**;\n");
	&push_pu_text("detach\n");
	$loop += 2;
	
	$loop = &analyze_semicolon($loop);

	return $loop;
}


sub analyze_break
{
	my $loop        = $_[0];
	my @local_array = @{$current_sentence->words};

	#/* break文 */
	my $break_mode = &get_current_break_mode();

	if ($local_array[$loop + 1] ne ";")
	{
		die "strange break sentence!\n";
	}

#	print "analyze break($break_mode) $loop, @local_array\n";
	if ($break_mode eq "loop")
	{
		#/* ループ処理中であれば、ループの終了 */
		&push_pu_text("break\n");
	}
	else
	{
		#/* ループ処理でなければ、switch ～ case文の終了 */
		if ( ($current_path->type eq "case") ||
		     ($current_path->type eq "default") )
		{
			#/* 残念ながら、if elseの両方でbreakした場合などは、拾えません */
			&push_pu_text("");
			$current_path->break(1);
		}
	}

	$loop++;
	$loop = &analyze_semicolon($loop);
	return $loop;
}


sub analyze_continue
{
	my $loop        = $_[0];

	#/* continue文 */
	#/* 解析対象外のワード */
	#/* 制御フローとしてはつながらないが、せめてdetachする */
	&push_pu_text("#pink:continue;\n");
	&push_pu_text("detach\n");
	$current_path->break(1);   #/* breakと同様、同一PATH内ではcontinue文の後ろに到達しない（goto labelを使わない限り） */

	return $loop;
}


sub analyze_return
{
	my $loop        = $_[0];
	my @local_array = @{$current_sentence->words};

	#/* return文 */
	my $ret_val = "";
	$loop++;
	while ($local_array[$loop] ne ";")
	{
		$ret_val = $ret_val . $local_array[$loop];
		$loop++;
	}

	if ($ret_val ne "")
	{
		&push_pu_text(":return $ret_val;\n");
#		print "return! value : $ret_val\n";
	}
	else
	{
#		print "no value return!\n";
	}

	&push_pu_text("stop\n");
	$current_path->break(1);

	$loop = &analyze_semicolon($loop);
	return $loop;
}


sub analyze_switch
{
	my $loop        = $_[0];
	my @local_array = @{$current_sentence->words};
	my $condition = "";

	#/* switch文 */
	($loop+1 < @local_array) or die "strange switch sentence!\n";

	if ($local_array[$loop+1] ne "(")
	{
		#/* switchの後に()が来ない。マクロ使っているやつ */
#		print "strange if sentence!\n";
		$loop++;
		$condition = $local_array[$loop];
	}
	else
	{
		$loop = &analyze_some_bracket($loop + 1, \$condition);
		if ($condition eq "")
		{
			#/* 空文だったら、次行に持ち越して処理継続する */
			$current_sentence->clear(0);
			$current_sentence->position($_[0]);
			return @local_array - 1;
		}

		#/* 一番外の()は取り除く */
		$condition =~ s/^\((.+)\)$/$1/;
	}

	$current_sentence->switch_val("(" . $condition . ")");
	&push_pu_text("partition \"switch - case\" {\n");
	&create_new_path("switch");
#	printf "switch : %s\n", $current_sentence->switch_val;
	return $loop;
}


sub analyze_for
{
	my $loop        = $_[0];
	my @local_array = @{$current_sentence->words};

#	print "analyze for! : @local_array\n";
	#/* for文 */
	my $init_condition;
	my $repeat_condition;
	my $pre_repeat_exec;

	#/* 初期化条件 */
	$init_condition = "";
	$loop += 2;
	while ($local_array[$loop] ne ";")
	{
		$init_condition = $init_condition . $local_array[$loop];
		$loop++;
	}


	#/* 実行条件 */
	$repeat_condition = "";
	$loop += 1;
	while ($local_array[$loop] ne ";")
	{
		$repeat_condition = $repeat_condition . $local_array[$loop];
		$loop++;
	}

	#/* 繰り返し処理 */
	$pre_repeat_exec = "";
	$loop += 1;
	while ($local_array[$loop] ne ")")
	{
		$pre_repeat_exec = $pre_repeat_exec . $local_array[$loop];
		$loop++;
	}

#	print "for ($init_condition  $repeat_condition  $pre_repeat_exec)\n";

	&push_pu_text("partition \"for loop\" {\n");
	if ($init_condition ne "")
	{
		&push_pu_text(":$init_condition]\n");
	}

	if ($repeat_condition eq "")
	{
		$repeat_condition = "TRUE";
	}

	&push_pu_text("while (" . CONT_SIZE . "$repeat_condition) is (" . CONT_SIZE . "Yes)\n");
	$current_sentence->backward($pre_repeat_exec);
	&create_new_path("for");
	return $loop;
}


sub analyze_while
{
	my $loop        = $_[0];
	my @local_array = @{$current_sentence->words};
	my $condition = "";


	#/* while文 */
#	print "analyze while!F $loop, @local_array\n";
	($loop+1 < @local_array) or die "strange while sentence!\n";

	if ($local_array[$loop+1] ne "(")
	{
		#/* whileの後に()が来ない。マクロ使っているやつ */
		$loop++;
		$condition = $local_array[$loop];
	}
	else
	{
		$loop = &analyze_some_bracket($loop + 1, \$condition);
		if ($condition eq "")
		{
			#/* 空文だったら、次行に持ち越して処理継続する */
			$current_sentence->clear(0);
			$current_sentence->position($_[0]);
			return @local_array - 1;
		}

		#/* 一番外の()は取り除く */
		$condition =~ s/^\((.+)\)$/$1/;
	}

	if ($current_path->type eq "do")
	{
		if ($loop+1 == @local_array)
		{
			#/* セミコロンが次行の場合は、持ち越す */
			$current_sentence->clear(0);
			$current_sentence->position($_[0]);
			return $loop;
		}

		($loop+1 < @local_array) or die "strange do while sentence1!\n";
		$loop++;
		($local_array[$loop] eq ";") or die "strange do while sentence2!\n";
		&push_pu_text("repeat while (" . CONT_SIZE . $condition . ") is (" . CONT_SIZE . "Yes) not (" . CONT_SIZE . "No)\n");
		&push_pu_text("}\n");

		#/* 親の実行PATHに復帰する */
		&return_parent_path();
		$loop = &analyze_semicolon($loop);
	}
	else
	{
		&push_pu_text("partition \"while loop\" {\n");
		&push_pu_text("while (" . CONT_SIZE . $condition . ") is (" . CONT_SIZE . "Yes)\n");
		&create_new_path("while");
	}

	return $loop;
}


sub analyze_else
{
	my $loop        = $_[0];
	my @local_array = @{$current_sentence->words};

	#/* else文 */
#	if ( ($loop + 1 >= @local_array) ||
#	     ($local_array[$loop + 1] ne "if") )
	if ($loop + 1 >= @local_array)
	{
		#/* else文の処理 : 最後に追加されているであろうendifをpopしてしまう */
#		print "analyze else!\n";
		pop @{$current_path->pu_text};
		pop @{$current_path->pu_text};
		&push_pu_text("else (" . CONT_SIZE . "No)\n");
		&create_new_path("else");
	}
	elsif ($local_array[$loop + 1] eq "if")
	{
#		print "else if!!!\n";
		$loop = &analyze_if($loop + 1);
	}
	else
	{
		die "strange else sentence!\n";
	}

	return $loop;
}


sub analyze_default
{
	my $loop        = $_[0];
	my @local_array = @{$current_sentence->words};

	#/* default文 */
	my $broke = 0;

	#/* すでにcase文に入っている場合は、親パスに復帰 */
	if ($current_path->type eq "case")
	{
		$broke = $current_path->break;
		if ($broke == 0)
		{
			#/* fall throughしてくるケース */
			&push_pu_text(":fall through}\n");
			&push_pu_text("detach\n");
		}
		&pop_path();
	}

	if ($current_path->type ne "switch")
	{
		die "strange default label without switch!\n";
	}

	if ($local_array[$loop + 1] ne ":")
	{
		die "strange default label without colon ( : ) !\n";
	}
	$loop++;

	$current_path->case_count($current_path->case_count + 1);
	if ($current_path->case_count == 1)
	{
		#/* いきなりdefault文が来た場合 */
		my $switch_val = $current_path->switch_val;

		$current_sentence->case_cond("if (". CONT_SIZE ."switch $switch_val) then (default)\n");
		&create_new_path("default");
	}
	else
	{
		$current_sentence->case_cond("elseif () then (" . CONT_SIZE . "default)\n");
		&create_new_path("default");
	}

	return $loop;
}


sub analyze_case
{
	my $loop        = $_[0];
	my @local_array = @{$current_sentence->words};

	#/* case文 */
	my $broke = 0;
	#/* すでにcase, default文に入っている場合は、親パスに復帰 */
	if ( ($current_path->type eq "case") ||
	     ($current_path->type eq "default") )
	{
		$broke = $current_path->break;
		if ($broke == 0)
		{
			#/* fall throughしてくるケース */
			&push_pu_text(":fall through}\n");
			&push_pu_text("detach\n");
		}
		&pop_path();
	}

	my $switch_val = $current_path->switch_val;

	if ($current_path->type ne "switch")
	{
		#/* 本当はif 分岐した中とか、ループの途中にもcase文を書けちゃいますが、そんなコードまで相手にしてられません！ */
		die "strange case label without switch!\n";
	}

	$loop++;
	while ($local_array[$loop] ne ":")
	{
		$current_sentence->case_val($current_sentence->case_val . $local_array[$loop]);
		$loop++;
	}

	if ($current_sentence->case_val =~ /^[^\(]/)
	{
		#/* ( 以外で開始していたら */
		$current_sentence->case_val("(" . $current_sentence->case_val . ")");
#		printf "add case value : %s\n", $current_sentence->case_val;
	}

	$current_path->case_count($current_path->case_count + 1);
#	printf "case : %s", $current_sentence->case_val;

	if ($current_path->case_count <= 0)
	{
		die "strange switch case sentence!!!\n";
	}
	elsif ($current_path->case_count == 1)
	{
		#/* 最初のcase文 */
		my $case_text = "if (" . CONT_SIZE . "switch $switch_val) then (" . CONT_SIZE . "case " . $current_sentence->case_val . ")";
		$current_sentence->case_cond($case_text);
		&create_new_path("case");
	}
	else
	{
		#/* 2個目以降のcase文 */
		my $case_text = "elseif () then (" . CONT_SIZE . "case " . $current_sentence->case_val . ")";
		$current_sentence->case_cond($case_text);
		&create_new_path("case");
	}

	return $loop;
}


#/* ネストを考慮して{}, (), []を一塊のテキストとして返す */
sub analyze_some_bracket
{
	my $loop         = $_[0];
	my $ref_out_text = $_[1];
	my $out_text     = "";

	my @local_array  = @{$current_sentence->words};
	my $open_bracket = $local_array[$loop];
	my $close_bracket = "";
	my $nest = 1;

	if ($open_bracket eq "{")
	{
		$close_bracket = "}";
	}
	elsif ($open_bracket eq "(")
	{
		$close_bracket = ")";
	}
	elsif ($open_bracket eq "[")
	{
		$close_bracket = "]";
	}
	else
	{
		die "no bracket type : $local_array[$loop]\n";
	}

	$out_text = $local_array[$loop];
	$loop++;
	while ($loop < @local_array)
	{
		$out_text = $out_text . " " . $local_array[$loop];
		if ($local_array[$loop] eq $open_bracket)
		{
			$nest++;
		}
		elsif ($local_array[$loop] eq $close_bracket)
		{
			$nest--;
		}

		if ($nest == 0)
		{
			last;
		}

		$loop++;
	}

	if ($nest == 0)
	{
		$$ref_out_text = $out_text;
	}
	else
	{
		#/* ネストが閉じきっていなかったら空文を返す。解析位置も進めない */
		$$ref_out_text = "";
		$loop = $_[0];
	}
	return $loop;
}


sub analyze_colon
{
	my $loop        = $_[0];
	my @local_array = @{$current_sentence->words};
	my $label_name = $local_array[$loop - 1];

#	print "label define!!!!! $label_name:\n";
	if ($label_name =~ /[^_A-Za-z0-9]/)
	{
		die "strange label define!!! [$label_name]\n";
	}

	my $label_num = &add_array_no_duplicate($current_function->label ,$label_name);
	my $color = &get_color_text($label_num);
	&push_pu_text("$color:**$label_name**;\n");
	$current_path->break(0);   #/* ラベルが貼られると、到達不可能コードではなくなる */

	return $loop;
}


#/* セミコロン */
sub analyze_semicolon
{
	my $loop        = $_[0];
	my @local_array = @{$current_sentence->words};
	my $path_type = $current_path->type;

#	print "analyze semicolon ($path_type) $loop, @local_array\n";
	if ($loop + 1 != @local_array)
	{
		#/* 文の途中で出てくるセミコロンは無視。(おそらくは構造体へのキャスト) */
		&add_free_word($local_array[$loop]);
		return $loop;
	}

	if ($current_path->pu_block ne "")
	{
		&add_free_word("\n");
	}

	#/* if文などで{}を使わないケースは、セミコロンでパス復帰する */
	if ($current_path->indent == $global_data->indent)
	{
		if ( ($path_type ne "case") &&
			($path_type ne "default") && 
			($path_type ne "do") )
		{
			#/* 親の実行PATHに復帰する */
			print "$path_type path without {}! @ " . $global_data->indent . " \n";
			&return_parent_path();
		}
	}

	return $loop;
}


sub analyze_bracket_open
{
	my $loop        = $_[0];
	my @local_array = @{$current_sentence->words};

	$global_data->indent($global_data->indent + 1);
	return $loop;
}

sub analyze_bracket_close
{
	my $loop        = $_[0];
	my @local_array = @{$current_sentence->words};

	#/* } 閉じる */
	$global_data->indent($global_data->indent - 1);
	if ($global_data->indent == 0)
	{
		&push_pu_text("");
		$global_data->in_function(0);
		push @{$current_function->texts}, $current_sentence->text;
		push @{$current_path->texts}, $current_sentence->text;
		push @functions, $current_function;

		if ($current_path->break == 0)
		{
			#/* breakしてないということは、return文の後ろではない！ */
			&push_pu_text("stop\n");
		}
	}
	elsif ($current_path->indent == $global_data->indent)
	{
		#/* do ～ while文以外は、親の実行パスに復帰する */
		if ($current_path->type ne "do")
		{
			&return_parent_path();
		}
	}
	elsif ($current_path->indent > $global_data->indent)
	{
		my $path_type = $current_path->type;
		&pop_path();

		#/* ここに来るのはswitch ～ case文のみ */
		if ( ($path_type eq "case") ||
		     ($path_type eq "default") )
		{
			print "return to switch path!\n";
			&push_pu_text("endif\n");
			&push_pu_text("}\n");

			if ($current_path->type ne "switch")
			{
				die "strange bracket close!!!! path : $path_type\n";
			}

			if ($current_path->indent != $global_data->indent)
			{
				die "strange bracket close in switch sentence!!!! path : $path_type\n";
			}

			&pop_path();
		}
		else
		{
			die "strange bracket close!!!! path : $path_type\n";
		}
	}
	else
	{
#		printf "current_path->type = %s\n", $current_path->type;
#		printf "current_path->indent = %d\n", $current_path->indent;
#		printf "indent_level = " . $global_data->indent . "\n";
	}
	return $loop;
}


sub analyze_ternary
{
	my $loop        = $_[0];
	my @local_array = @{$current_sentence->words};

	#/* 三項演算子 */

	#/* 末尾がセミコロンではない */
	if ($local_array[@local_array - 1] ne ";")
	{
		#/* 次行に持ち越し */
		$current_sentence->clear(0);
		$current_sentence->position($loop);
		return @local_array - 1;
	}

	#/* とりあえず、行末まで全部一つの処理として扱う */
	while ($loop < @local_array - 1)
	{
		&add_free_word($local_array[$loop]);
		$loop++;
	}

	return $loop - 1;
}


#/* 関数内の文の種類を先頭2語で判別する */
sub analyze_function_sentence_type
{
	my @local_array = @{$current_sentence->words};
	my $word = $local_array[0];

	if ($word =~ /^(for|if|else|goto|continue|do|while|break|case|switch|default|return|\{|\})$/)
	{
		return SENTENCE_CONTROL;
	}
	elsif ($word =~ /^(static|extern|inline|const|volatile|unsigned|signed|auto)$/)
	{
		return SENTENCE_DECLARE;
	}
	elsif ($word =~ /^(struct|union|enum|typedef)$/)
	{
		return SENTENCE_DECLARE;
	}
	elsif ($word =~ /^(void|char|int|short|long|float|double)$/)
	{
		return SENTENCE_DECLARE;
	}
	elsif ($word =~ /^(\;|\,)$/)
	{
		return SENTENCE_DECLARE;
	}
	elsif ($word =~ /^(\(|\+\+|\-\-|\+|\-|\~|\*|\!|\&)$/)
	{
		return SENTENCE_FORMULA;
	}
	elsif ($word =~ /^([0-9]+)/)
	{
		return SENTENCE_FORMULA;
	}
	elsif ($word =~ /([_A-Za-z][_A-Za-z0-9]*)/)
	{
		(@local_array > 1) or die "strange sentence0!\n";

		if ($local_array[1] eq ":")
		{
			#/* ラベルの場合 */
			return SENTENCE_FORMULA;
		}
		elsif (check_typedefs($word))
		{
			#/* 既知の型の場合 */
			return SENTENCE_DECLARE;
		}

		return &analyze_function_second_word($local_array[1]);
	}

	die "strange first word! $word\n";
	return SENTENCE_UNKNOWN;
}


#/* 関数内の2語目の解析 */
sub analyze_function_second_word
{
	my $word = $_[0];

	if ($word =~ /^(static|extern|inline|const|volatile|unsigned|signed|auto)$/)
	{
		return SENTENCE_DECLARE;
	}
	elsif ($word =~ /^(struct|union|enum|typedef)$/)
	{
		return SENTENCE_DECLARE;
	}
	elsif ($word =~ /^(void|char|int|short|long|float|double)$/)
	{
		return SENTENCE_DECLARE;
	}
	elsif ($word =~ /^(\;|\,)$/)
	{
		return SENTENCE_DECLARE;
	}
	elsif ($word =~ /([_A-Za-z][_A-Za-z0-9]*)/)
	{
		return SENTENCE_DECLARE;
	}

	return SENTENCE_FORMULA;
}


#/* 関数内の宣言文の解析 */
sub analyze_declare_sentence
{
	my $loop = 0;
	my @local_array = @{$current_sentence->words};

	$loop = &analyze_global_first_word($loop);
	if ($current_sentence->typ_fixed == 0)
	{
		#/* セミコロンだけの空文の場合、無視 */
		($loop == 1) or die "strange declare sentence! $loop, @local_array\n";
		return;
	}

	$loop = &analyze_global_second_word($loop);
	if (($current_sentence->is_func == 0) ||
		($current_sentence->astarisk_f > 0)) {
		if ($current_sentence->name_fixed) {
			&add_variable();
		}
	}

	return $loop;
}

#/* 関数内の宣言文の1行解析 */
sub analyze_declare_line
{
	my $loop;
	my @local_array = @{$current_sentence->words};
	my $nest = 0;

	$current_sentence->clear(0);
	for ($loop = $current_sentence->position; $loop < @local_array; $loop++)
	{
		#/* 文末のセミコロンを見つける */
		if ($local_array[$loop] eq ";")
		{
			if ($nest == 0)
			{
				&analyze_declare_sentence();
				$current_sentence->clear(1);
			}
		}
		elsif ($local_array[$loop] eq "{")
		{
			$nest++;
		}
		elsif ($local_array[$loop] eq "}")
		{
			$nest--;
		}
	}
}


#/* 関数内の式の解析 */
sub analyze_formula_sentence
{
	my $loop = 0;
	my @local_array = @{$current_sentence->words};

	for ($loop = $current_sentence->position; $loop < @local_array; $loop++)
	{
		if (exists $analyze_in_funcs{$local_array[$loop]}) 
		{
#			print "analyze in func2 $loop, @local_array\n";
			my $func = $analyze_in_funcs{$local_array[$loop]};
			$loop = &$func($loop);
		}
		else
		{
			#/* 解析対象外のワード */
			&add_free_word($local_array[$loop]);
		}
	}

	return $loop;
}


sub analyze_formula_line
{
	my $loop;
	my @local_array = @{$current_sentence->words};
	my $nest = 0;

	if ($local_array[@local_array - 1] eq ":")
	{
		#/* ラベル */
		&analyze_colon(@local_array - 1);
		return;
	}

	$current_sentence->clear(0);
	for ($loop = $current_sentence->position; $loop < @local_array; $loop++)
	{
		#/* 文末のセミコロンを見つける */
		if ($local_array[$loop] eq ";")
		{
			if ($nest == 0)
			{
				&analyze_formula_sentence();
				$current_sentence->clear(1);
			}
		}
		elsif ($local_array[$loop] eq "{")
		{
			$nest++;
		}
		elsif ($local_array[$loop] eq "}")
		{
			$nest--;
		}
	}
}


#/* 関数内の1行解析 */
sub analyze_function_line
{
	my $loop;
	my @local_array = @{$current_sentence->words};
	my $sentence_type = SENTENCE_UNKNOWN;

	$current_sentence->clear(1);

#	&disp_current_words();
	if (@local_array == 0)
	{
		#/* 空行 */
		&clear_current_sentence();
		return;
	}

	$sentence_type = &analyze_function_sentence_type();
	$current_sentence->sentence($sentence_type);
	if ($sentence_type == SENTENCE_CONTROL)
	{
		#/* 制御文の処理 */
		my $func = $analyze_controls{$local_array[0]};
		&$func(0);
	}
	elsif ($sentence_type == SENTENCE_DECLARE)
	{
		&analyze_declare_line();
	}
	else
	{
		&analyze_formula_line();
	}

	if ($current_sentence->clear == 1)
	{
		if ($global_data->in_function == 1)
		{
			push @{$current_function->texts}, $current_sentence->text;
			push @{$current_path->texts}, $current_sentence->text;
		}

		&clear_current_sentence();
	}
}


sub create_new_path
{
	my $child_num;
	my $path_type = $_[0];

	if ($current_sentence->case_val ne "")
	{
		($current_path->type eq "switch") or die "not switch!\n";
		push @{$current_path->case_val}, $current_sentence->case_val;
	}

#	print "new path! $loop, @local_array\n";
	$child_num = @{$current_path->child};
	&push_pu_text("Link to child[$child_num]\n");
	&new_path($path_type, $current_path, $global_data->indent);
	
	if ($current_sentence->case_cond ne "")
	{
		my $push_text = $current_sentence->case_cond;
		&push_pu_text("$push_text\n");
	}
}


#/* C解析結果の出力 */
sub output_result
{
	my $source_file  = $_[0];
	my $out_file     = "";
	my $include;
	my $function;
	my $variable;
	my $arg_type;
	my $arg_name;
	my $loop;
	my @pu_files = ();

	printf OUT_FILE_OUT "Total Lines\t%s\n", $global_data->lines;
	printf OUT_FILE_OUT "Total Comment\t%s\n", $global_data->comment;
	printf OUT_FILE_OUT "Include Files\n";
	foreach $include (@include_files)
	{
		print OUT_FILE_OUT "\t$include\n";
	}

	printf OUT_FILE_OUT "\ntype defs\n";
	printf OUT_FILE_OUT "\tname\ttype\n";
	foreach my $key (sort(keys(%global_typedefs)))
	{
		printf OUT_FILE_OUT "\t%s\t%s\n", $key,$global_typedefs{$key};
	}


	printf OUT_FILE_OUT "\nVariables List\n";
	printf OUT_FILE_OUT "\ttype\tname\tinit\tcomment\tstatic\textern\n";
	foreach $variable (@global_variables)
	{
		printf OUT_FILE_OUT "\t%s\t%s\t%s\t%s\t%s\t%s\n", $variable->typ,$variable->name,$variable->init_val,$variable->comment_txt,$variable->static,$variable->extern;
	}

	printf OUT_FILE_OUT "\nFunction List\n";
	printf OUT_FILE_OUT "\tname\tret_type\tlines\tsummary\tcomment\tstatic\n";
	foreach $function (@functions)
	{
		printf OUT_FILE_OUT "\t%s\t%s\t%s\t%s\t%s\t%s\n", $function->name,$function->ret_typ,$function->lines,$function->summary,$function->comment,$function->static;
	}

	printf OUT_FILE_OUT "\nFunction Detail\n";
	foreach $function (@functions)
	{
		my $name = $function->name;
		my $path = $function->path;

		make_directory($output_fld . "/" . basename($source_file));
		$out_file = $output_fld . "/" . basename($source_file) . "/" . "$name.pu";
		open(OUT_PU_OUT,">$out_file")   || die "Can't create analyzed.pu file.\n";

		printf OUT_PU_OUT "\@startuml\n";
		printf OUT_PU_OUT "!pragma useVerticalIf on\n";
		printf OUT_PU_OUT "skinparam ConditionEndStyle hline\n";

#		printf OUT_PU_OUT "floating note:$name()\n";
		printf OUT_PU_OUT "title <size:32>$name()</size>\n";
#		printf OUT_FILE_OUT "\t%s\t%s\t%s\t%s\n", $function->name,$function->ret_typ,$function->lines,$function->comment;
		
		printf OUT_FILE_OUT "\tName  \t%s\n", $function->name;
		printf OUT_FILE_OUT "\tReturn\t%s\n", $function->ret_typ;

		for ($loop = 0; $loop < @{$function->args_typ}; $loop++)
		{
			$arg_type = $function->args_typ($loop);
			$arg_name = $function->args_name($loop);
			printf OUT_FILE_OUT "\tArg[%s]\t%s\t%s\n", $loop, $arg_type, $arg_name;
		}

		printf OUT_FILE_OUT "\tLocal Variable\n";
		printf OUT_FILE_OUT "\ttype\tname\tinit\tcomment\tstatic\textern\n";
#		foreach $variable (@{$function->local_val})
		for ($loop = 0; $loop < @{$function->local_val}; $loop++)
		{
			my $variable = ${$function->local_val}[$loop];
			printf OUT_FILE_OUT "\t%s\t%s\t%s\t%s\t%s\t%s\n", $variable->typ,$variable->name,$variable->init_val,$variable->comment_txt,$variable->static,$variable->extern;
		}

		printf OUT_FILE_OUT "\tFunctions call to\n";
		for ($loop = 0; $loop < @{$function->func_call}; $loop++)
		{
			my $function = $function->func_call($loop);
			printf OUT_FILE_OUT "\t[%s]\t%s\n", $loop, $function;
		}
		printf OUT_FILE_OUT "\tcalled from\n";
		for ($loop = 0; $loop < @{$function->func_ref}; $loop++)
		{
			my $function = $function->func_ref($loop);
			printf OUT_FILE_OUT "\t[%s]\t%s\n", $loop, $function;
		}
		printf OUT_FILE_OUT "\n";

		printf OUT_PU_OUT "start\n";
		&output_path($path);
		printf OUT_PU_OUT "footer auto-generated by c_analyze(https://github.com/Hakeem34/c_analyze)\n";
		printf OUT_PU_OUT "\@enduml\n\n";
		close(OUT_PU_OUT);
		push @pu_files, $out_file;
	}
	
	if ($jar_path ne "")
	{
		print "do pu convert!!! @pu_files\n";
		system("java -DPLANTUML_LIMIT_SIZE=16384 -jar $jar_path @pu_files")
	}

	#/* 関数コールツリーの作成 */
	$out_file = $output_fld . "/" . basename($source_file) . "_func_tree.pu";
	open(OUT_FUNC_TREE,">$out_file")   || die "Can't create func_tree.pu file.\n";
	printf OUT_FUNC_TREE "\@startmindmap\n";
	printf OUT_FUNC_TREE "* global functions\n";
	foreach $function (@functions)
	{
		if ($function->static == 0)
		{
			&make_func_call_tree($function, 2);
		}
	}
	printf OUT_FUNC_TREE "footer auto-generated by c_analyze(https://github.com/Hakeem34/c_analyze)\n";
	printf OUT_FUNC_TREE "\@endmindmap\n";

	if ($jar_path ne "")
	{
		print "do pu convert!!! $out_file\n";
		system("java -DPLANTUML_LIMIT_SIZE=16384 -jar $jar_path $out_file")
	}

	close(OUT_FUNC_TREE);
}


#/* 関数呼び出しツリーの生成（再帰） */
sub make_func_call_tree
{
	my $function = $_[0];
	my $level    = $_[1];
	my $func_ref;
	my $loop;
	my @local_func_call = @{$function->func_call};
	my $local_func_count = @local_func_call;

	printf "func:%s,  level:%d, local_func_call[$local_func_count] = @local_func_call\n", $function->name, $level;
	
	if ($function->make_tree == 0)
	{
		printf OUT_FUNC_TREE "*" x $level . " " . $function->name . "\n";
		if ( ($level == 2) ||
		     ($function->static == 1) )
		{
			#/* 最初の呼び出しか、あるいは自身がスタティック関数だったら再帰していく */
			$function->make_tree(1);
			for ($loop = 0; $loop < $local_func_count; $loop++)
			{
	#			printf "func_call:%s\n", $local_func_call[$loop];
				$func_ref = &check_func_name($local_func_call[$loop]);
				if ($func_ref ne "")
				{
					&make_func_call_tree($func_ref, $level+1);
				}
				else
				{
	#				print "not found! [$local_func_count] $level\n";
				}
			}
		}
		else
		{
			#/* 自身がグローバル関数だったらこれ以上掘り下げない */
		}
	}
	else
	{
		printf OUT_FUNC_TREE "*" x $level . "_ " . $function->name . "(*)\n";
	}

}


#/* break文がswitchに対してか、あるいはループに対してかを判定 */
sub get_current_break_mode
{
	my $path = $current_path;
	my $mode = $path->type;

#	print "mode : $mode\n";
	while ( ($mode ne "switch") &&
	        ($mode ne "do") &&
	        ($mode ne "while") &&
	        ($mode ne "for") )
	{
		$path = $path->parent;
		if ($path eq "")
		{
			die "not found break root path!\n";
		}

		$mode = $path->type;
#		print "mode : $mode\n";
	}

	if ($mode eq "switch")
	{
		return "switch";
	}
	else
	{
		return "loop";
	}
}


#/* puテキストの追加処理（インデントを付加する） */
sub push_pu_text
{
	my $pu_text = $_[0];
	my $path_level = $current_path->level;
	my $indent_tab = "\t" x $path_level;
	my $block_text = "";

#	$pu_text =~ s/\n([^\n])/\n$indent_tab$1/g;

#	print "push_pu_text : $pu_text";
	if ($current_path->pu_block ne "")
	{
		#/* pu_blockのテキストが溜まっていれば、先に出力する */
		if ( ($current_path->break == 1) ||
		     ($current_path->type eq "switch") )
		{
			print "never reach this block!!!!\n";
			$block_text = "#HotPink:You cannot reach this block!\n" . $current_path->pu_block;
		}
		else
		{
			$block_text = ":" . $current_path->pu_block;
		}

		#/* 末尾の改行をブロックの終端に置き換える */
		if ( ($current_path->call_block == 0) ||
			 ($block_text =~ /\|/) )
		{
			#/* 関数コールを含むブロックは|を使って二重線のブロックにするが、文中に|が含まれている場合は、PlantUMLがsyntax errorを起こすので回避する */
			$block_text =~ s/\n$/]\n/
		}
		else
		{
			$block_text =~ s/\n$/|\n/
		}

#		print "push pu_block!!!\n";
		push @{$current_path->pu_text}, $indent_tab . $block_text;
		$current_path->pu_block("");
		$current_path->call_block(0);
	}

	if ($pu_text ne "")
	{
		push @{$current_path->pu_text}, $indent_tab . $pu_text;
	}
}


#/* 子パスに入りなおす */
sub re_enter_latest_child
{
	my $child_path;

	$child_path = $current_path->child(@{$current_path->child}-1);
	$current_path = $child_path;
}


#/* 親の実行PATHに復帰する */
sub return_parent_path
{
	my $path_type = $current_path->type;
	my $backward_text = $current_path->backward;
	&pop_path();
	if ($path_type eq "if")
	{
#		print "return from if path : $current_path->pu_text\n";
		&push_pu_text("else (" . CONT_SIZE . "No)\n");
		&push_pu_text("endif\n");
	}
	elsif ($path_type eq "else")
	{
		&push_pu_text("endif\n");
	}
	elsif ($path_type eq "while")
	{
		&push_pu_text("endwhile (" . CONT_SIZE . "No)\n");
		&push_pu_text("}\n");
	}
	elsif ($path_type eq "for")
	{
		#/* for文の終わりには繰り返し前の処理とendwhileを挿入する */
		if ($backward_text ne "")
		{
			&push_pu_text("backward :$backward_text]\n");
		}

		&push_pu_text("endwhile (" . CONT_SIZE . "No)\n");
		&push_pu_text("}\n");
	}
	elsif ($path_type eq "do")
	{
		#/* do while文はwhileの部分でpathを閉じるので、ここでは何もしない */
	}
	elsif ($path_type eq "switch")
	{
		#/* ここに来るのはcaseもdefaultもないswitch文！ */
		print "switch sentence with no case or default!!!!\n";
		&push_pu_text("#HotPink:No case or default label!]\n");
		&push_pu_text("}\n");
	}
	elsif ( ($path_type eq "case") ||
	        ($path_type eq "default") )
	{
		print "close bracket in case, default\n";
	}
	else
	{
		print "unhandled path close!!!!!! path:$path_type\n";
	}
}


#/* 呼び出し関数リストに追加する(重複チェック) */
sub add_function_call
{
	my $call_function = $_[0];
	my $function_listed = "";
	my $match = 0;

	#/* 現在の実行パスの呼び出し関数リストに追加する */
	foreach $function_listed (@{$current_path->func_call})
	{
		if ($function_listed eq $call_function)
		{
			$match = 1;
			last;
		}
	}

	if ($match == 0)
	{
		push @{$current_path->func_call}, $call_function;
	}


	#/* 現在の関数の呼び出し関数リストに追加する */
	$match = 0;
	foreach $function_listed (@{$current_function->func_call})
	{
		if ($function_listed eq $call_function)
		{
			$match = 1;
			last;
		}
	}

	if ($match == 0)
	{
		push @{$current_function->func_call}, $call_function;
	}
}


#/* 引数で指定した名前の関数がモジュール内に存在するか、した場合はそのオブジェクトを返す */
sub check_func_name
{
	my $name = $_[0];
	my $function;

	foreach $function (@functions)
	{
		if ($function->name eq $name)
		{
			return $function;
		}
	}

	return "";
}


#/* typedefの型定義リストに含まれる型かどうかをチェックする */
sub check_typedefs
{
	my $name = $_[0];

	if (exists ($global_typedefs{$name}))
	{
		return 1;
	}

	if (exists (${$current_function->typedefs}{$name}))
	{
		return 1;
	}

	return 0;
}


#/* モジュール内の参照関係を確認 */
sub check_reference
{
	my $function = $_[0];
	my $func_name;
	my $func_refs;

	foreach $func_name (@{$function->func_call})
	{
		$func_refs = &check_func_name($func_name);
		if ($func_refs ne "")
		{
			#/* 参照している関数側の被参照関数に追加する */
			printf "func call!!!!!!! [%s]\n", $func_refs->name;
			push @{$func_refs->func_ref}, $function->name;
		}
	}
}


#/* 配列に重複を避けて要素を追加する     */
#/* 戻り値はその要素のインデックスを返す */
sub add_array_no_duplicate
{
	my ($array, $value) = @_;
	my $loop;

	for ($loop = 0; $loop < @$array; $loop++)
	{
		if (@$array[$loop] eq $value)
		{
			return $loop;
		}
	}

	push @$array, $value;
	return $loop;
}


#/* goto label用の色（4つ以上のラベルとgotoを使うような関数は書き直せ！ という主張） */
sub get_color_text
{
	my $val = $_[0];
	my $color = "#red";

	$val = $val % 4;
	
	if ($val == 0)
	{
		$color = "#lime";
	}
	elsif ($val == 1)
	{
		$color = "#aqua";
	}
	elsif ($val == 2)
	{
		$color = "#yellow";
	}

	return $color;
}


#/* 一つの実行PATHの出力（再帰する） */
sub output_path
{
	my $path = $_[0];
	my $text;

	foreach $text (@{$path->texts})
	{
		printf OUT_FILE_OUT "\t$text";
	}

	foreach $text (@{$path->pu_text})
	{
		if ($text =~ /^\t*Link to child\[([0-9]+)\]\n/)
		{
			my $path_level = $path->level;
#			print "Link $path_level - $1\n";
			my $child_path = $path->child($1);
			output_path($child_path);
		}
		else
		{
			$text = restore_literal($text);
			print OUT_PU_OUT $text;
		}
	}
}


#/* 設定ファイルの読み込み処理 */
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

		if ($line_text =~ /^define\s+([A-Za-z_][A-Za-z0-9_]*)\(([^\)]*)\)\s+(.*)\n/)
		{
			my $macro_name = $1;
			my $second_part = $3;

			print "define $macro_name($2) : $3\n";
			&new_macro("$macro_name", $3, $2);
		}
		elsif ($line_text =~ /^define[ \t]+([_A-Za-z][_A-Za-z0-9]*)[ \t]+([^\s]+)/)
		{
			print "define $1 as $2\n";
			&new_macro($1, $2, "");
		}
		elsif ($line_text =~ /^define[ \t]+([_A-Za-z][_A-Za-z0-9]*)[ \t]*/)
		{
			print "define $1\n";
			&new_macro($1, "", "");
		}
		elsif ($line_text =~ /^incpath[ \t]+([^\s]+)/)
		{
			print "include path $1\n";
			&add_array_no_duplicate(\@include_paths ,$1);
		}
		elsif ($line_text =~ /^extract[ \t]+([_A-Za-z][_A-Za-z0-9]*)/)
		{
			print "extract $1\n";
			&add_array_no_duplicate(\@extracts ,$1);
		}
		elsif ($line_text =~ /^include[ \t]+([^\s]+)/)
		{
			print "add target include file $1\n";
			&add_array_no_duplicate(\@target_include ,$1);
		}
		elsif ($line_text =~ /^plantuml[ \t]+([^\s]+)/)
		{
			print "plantuml.jar path specified.\n";
			$jar_path = $1;
		}
	}
	close(SETTING_IN);
}


