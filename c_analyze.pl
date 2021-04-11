#############################################################################
# C言語プログラム解析スクリプト
#
# 概要：
#   関数フロー及び単体試験項目の抽出を目的とする
#
#############################################################################
use strict;
use warnings;

use File::Basename;
use File::Path;
use File::Copy;
use Class::Struct;
use Cwd;


struct GlobalInfo => {
	lines        => '$',       #/* 行数                       */
	comment      => '$',       #/* コメント行数               */
	indent       => '$',       #/* 現在のインデント           */
	section      => '$',       #/* 現在のセクション           */
	in_function  => '$',       #/* 現在のスコープ             */
	bracket_type => '$',       #/* 現在の{}タイプ             */
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
	local_type => '@',       #/* ローカル定義の型           */
};


#/* 実行パスを表す構造体。分岐しない一連の処理 */
struct Path => {
	function   => '$',       #/* 所属する関数               */
	lines      => '$',       #/* 行数                       */
	type       => '$',       #/* パス種別                   */
	texts      => '@',       #/* 原文                       */
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
	init        => '$',       #/* 初期値                     */
	extern      => '$',       #/* 外部変数か？               */
	static      => '$',       #/* スタティックか？           */
	const       => '$',       #/* 定数か？                   */
	array       => '$',       #/* 配列か？                   */
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
	init       => '$',       #/* 初期値                     */
	extern     => '$',       #/* 修飾子extern有無           */
	static     => '$',       #/* 修飾子static有無           */
	const      => '$',       #/* 修飾子const有無            */
	unsigned   => '$',       #/* 修飾子unsigned有無         */
	control    => '$',       #/* 制御文                     */
	struct     => '$',       #/* struct/union/enumの有無    */
	array      => '$',       #/* []の有無                   */
	words      => '@',       #/* 単語                       */
	position   => '$',       #/* 解析位置                   */
	astarisk   => '$',       #/* アスタリスク               */
	is_func    => '$',       #/* 関数？                     */
	init_nest  => '$',       #/* 初期値の{}ネスト           */
	temp       => '$',       #/* テンポラリ                 */

	clear      => '$',       #/* クリア実施フラグ           */
	new_path   => '$',       #/* 子パスのタイプ             */
	backward   => '$',       #/* for文の繰り返し処理        */
	switch_val => '$',       #/* switch文の評価値           */
	pu_text    => '$',       #/* アクティビティ図用         */
	case_val   => '$',       #/* caseラベルの値             */
	func_call  => '$',       #/* コールする関数             */
	case_condition   => '$', #/*                            */
	pop_current_path => '$', #/*                            */
};



#/* ファイル間で共通の変数 */
my @c_prepro_word = ("include", "define", "undef", "pragma", "else", "endif", "elif", "ifdef", "ifndef", "error", "if");
my $output_fld = "c_analyze";
my @include_paths  = ();
my @target_include = ();
my @target_files = ();
my $setting_file = "c_analyze_setting.txt";
my $output_temp_text = 0;
my $output_remain = "";
my @output_lines;
my @input_lines;
my $pu_convert = 1;


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
my @valid_define_name  = ();		#/* 有効なdefine値を列挙 */
my @valid_define_value = ();

#/* C言語の解析に使う変数 */
my @include_files  = ();
my @variables = ();
my @functions = ();
my $current_function = "";
my @path_stack = ();
my $current_path = "";
my $global_data = GlobalInfo->new();
my $current_sentence = CurrentSentence->new();
my $prev_word = "";
my $force_prev_word = "";
my $first_comment    = "";			#/* コメントブロックの最初     */
my $current_comment  = "";			#/* 直近のコメント（単行）     */
my $current_comments = "";			#/* 直近のコメント（累積）     */
my $current_brief    = "";			#/* 直近の@briefコメント       */
my $in_define = 0;
my $type_define = 0;
my @literals = ();
my %typedefs = ();					#/* 型定義のハッシュ */

my @prepare_funcs = (\&comment_parse, \&line_backslash_parse, \&line_define_parse, \&line_parse, \&line_indent_parse);
my %analyze_funcs = (
                        'if'      => \&analyze_if,      'else'    => \&analyze_else,      'do'       => \&analyze_do,       '{'       => \&analyze_bracket_open,
                        'break'   => \&analyze_break,   'case'    => \&analyze_case,      'continue' => \&analyze_continue, '}'       => \&analyze_bracket_close,
                        'goto'    => \&analyze_goto,    'for'     => \&analyze_for,       'switch'   => \&analyze_switch,   '('       => \&analyze_round_bracket_open,
                        ':'       => \&analyze_colon,   ';'       => \&analyze_semicolon, '?'        => \&analyze_ternary,  ')'       => \&analyze_round_bracket_close,
                        '='       => \&analyze_equal,   'default' => \&analyze_default,   'while'    => \&analyze_while,    'return'  => \&analyze_return,
                        'typedef' => \&analyze_typedef,                                                                     '['       => \&analyze_square_bracket_open,
                                                                                                                            ']'       => \&analyze_square_bracket_close,
#                       'union'   => \&analyze_union,   'enum'    => \&analyze_enum,      'struct'   => \&analyze_struct,   
                    );

&main();

sub init_variables
{
	$is_comment = 0;
	$is_single_comment = 0;
	$is_literal = 0;
	$line_postpone = "";
	@valid_define_name  = ();		#/* 有効なdefine値を列挙 */
	@valid_define_value = ();
	@include_files  = ();
	@variables = ();
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
	$prev_word = "";
	$force_prev_word = "";
	$first_comment    = "";			#/* コメントブロックの最初     */
	$current_comment  = "";			#/* 直近のコメント（単行）     */
	$current_comments = "";			#/* 直近のコメント（累積）     */
	$current_brief    = "";			#/* 直近の@briefコメント       */
	$in_define = 0;
	$type_define = 0;
	@literals = ();
	@valid_line = (1);
	@once_valid = (1);
	$nest_level   = 0;
	$indent_level = 0;
	%typedefs = ();					#/* 型定義のハッシュ */
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

	if ($output_temp_text)
	{
#		print "input : $local_line\n";
		print OUT_FILE_OUT $local_line;
	}

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

	if ($output_temp_text)
	{
		$out_file = $output_fld . "/" . basename($source_file) . "_temp$proc_num.txt";
		open(OUT_FILE_OUT,">$out_file")   || die "Can't create out file.\n";
	}

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
		close(OUT_FILE_OUT);

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
	open(SOURCE_IN,"$source_file") || die "Can't open source file.\n";
	while ( <SOURCE_IN> )
	{
		push @input_lines, $_;
	}
	close(SOURCE_IN);


	for ($loop = 0; $loop < 5; $loop++)
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


#/* コメントの分離処理 */
sub comment_parse
{
	my $local_line = $_[0];

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
	elsif ($is_literal == 1)
	{
		#/* リテラル行の継続 */
		if ($local_line =~/(\")/)
		{
			$line_postpone = $line_postpone . $` . "\"";
			$is_literal = 0;
			&comment_parse($');
		}
		elsif ($local_line =~/\\\s*\n/)
		{
			print "Literal goes next line!\n";
			&output_line($line_postpone . $local_line);
			$line_postpone = "";
		}
		else
		{
			print "missing terminating \" character\n";
		}
	}
	elsif ($local_line =~/(\/\/|\/\*|\")/)
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
		elsif ($1 eq "\"")
		{
			$line_rear = $';
			if ($line_rear =~/\"/)
			{
#				print "Literal!\n";
				$line_postpone = $line_postpone . $line_front . "\"" . $` . "\"";
				&comment_parse($');
			}
			elsif ($line_rear =~/\\\s*\n/)
			{
#				print "Literal goes next line!\n";
				$is_literal = 1;
				&output_line($line_postpone . $local_line);
				$line_postpone = "";
			}
			else
			{
				print "missing terminating \" character\n";
			}
		}
		else
		{
#			print "C Style Comment! $local_line\n";
			$line_rear = $';
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
sub is_valid_define_name
{
	my $define;

	foreach $define (@valid_define_name)
	{
		if ($_[0] eq $define)
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
			if ($local_line =~ /([\;\{\}])\s*\n/)
			{
				#/* ; か { か } で終わっている行は、末尾のスペースを除去 */
#				print "not joint $local_line\n";
				$local_line =~ s/([\;\{\}])\s*\n/$1\n/
			}
			elsif ($local_line =~ /([^\;\{\}])\s*\n/)
			{
				#/* ; か { か } で終わってない行は、スペース1個空けて連結する */
#				print "joint $local_line\n";
				$line_postpone = "$`$1 ";
			}
			else
			{
#				print "What? $local_line\n";
			}
		}
	}

	if ($line_postpone eq "")
	{
		#/* 行頭の処理がめんどうなので、とりあえず半角スペースをつけてしまう */
		$local_line = " " . $local_line;

		if ($local_line =~ /^\s*\#/)
		{
			#/* ディレクティブは除外 */
		}
		else
		{
			#/* リテラルを全部置き換えてしまう。名前がぶつかったらすいません。。。 */
			while (($index = index($local_line, "\"")) != -1)
			{
				my $line_front = substr($local_line, 0, $index + 1);
				my $line_rear = substr($local_line, $index + 1);
#				print "find literal in $line_front $line_rear";

				if ($line_rear =~ /([^\\])\"/)
				{
					my $local_literal = "\"$`$1\"";
					print "literal2 is $local_literal\n";
					my $literal_num = @literals;
					push @literals, $local_literal;
#					$local_line =~ s/$local_literal/\__C_ANALYZE_LITERALS_$literal_num/;
					substr($local_line,  $index, length($local_literal), "__C_ANALYZE_LITERALS_$literal_num");
				}
				elsif ($line_rear =~ /^\"/)
				{
					my $local_literal = "\"\"";
					print "literal1 is $local_literal\n";
					my $literal_num = @literals;
					push @literals, $local_literal;
					substr($local_line,  $index, length($local_literal), "__C_ANALYZE_LITERALS_$literal_num");
				}
				else
				{
#					print "literal not found in $line_rear";
					die "literal end not found!\n";
				}
			}
		}

		&output_line($local_line);
	}
}


#/* defineマクロの置き換え実施 */
sub replace_define
{
	my $text  = $_[0];
	my $define;
	my $value;
	my $index;
	my $count;

#	print "replace [$text] to ";
	$count = @valid_define_name;
	for ($index = 0; $index < $count; $index++)
	{
		$text =~ s/$valid_define_name[$index]/$valid_define_value[$index]/g;
	}
#	print "[$text]\n";

	return $text;
}


#/* マクロ定義の追加処理 */
sub add_valid_define
{
	my $name  = $_[0];
	my $value = $_[1];
	my $define;
	my $index;
	my $count = @valid_define_name;

	foreach $define (@valid_define_name)
	{
		if ($define eq $name)
		{
#			print "Already defined!\n";
			return;
		}
	}

	if ($count == 0)
	{
		#/* 要素0ならとにかくPush */
#		print "new define1! $name, $value\n";
		push @valid_define_name,  $name;
		push @valid_define_value, $value;
	}
	else
	{
	
		for ($index = 0; $index < $count; $index++)
		{
			if (length($valid_define_name[$index]) < length($name))
			{
				#/* 長い順にソートして配列にしていく */
#				print "new define2! $name, $value\n";
				splice(@valid_define_name,  $index, 0, $name);
				splice(@valid_define_value, $index, 0, $value);
				return;
			}
		}

		#/* 最短であった場合は末尾に足す */
#		print "new define3! $name, $value\n";
		push @valid_define_name,  $name;
		push @valid_define_value, $value;
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
			
			if ($local_line =~ /\#define\s+([A-Za-z_][A-Za-z0-9_]*)\(([^\)]*)\)(.*)\n/)
			{
				my $macro_name = $1;
				my $second_part = $3;

#				print "#define macro func! $macro_name($2) : $3\n";
				add_valid_define("$macro_name($2)", $3);
				&output_line($local_line);
			}
			elsif ($local_line =~ /\#define\s+([A-Za-z_][A-Za-z0-9_]*)\s+(.*)\n/)
			{
				#/* マクロの定義 */
				if ($valid_now == 1)
				{
					my $macro_name = $1;
					my $second_part = $2;
					
					if ($second_part =~ /\#/)
					{
						print "invalid define value! $macro_name : $second_part\n";
						add_valid_define($macro_name, "");
					}
					else
					{
#						print "#define macro! $macro_name : $second_part\n";
						add_valid_define($macro_name, $second_part);
					}

					&output_line($local_line);
				}
			}
			elsif ($local_line =~ /\#define\s+([A-Za-z_][A-Za-z0-9_]*)\s*\n/)
			{
				#/* マクロの定義 */
				if ($valid_now == 1)
				{
#					print "#define macro only! $1\n";
					add_valid_define($1, "");

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

					for ($index = 0; $index < @valid_define_name; $index++)
					{
						if ($valid_define_name[$index] eq $1)
						{
							splice @valid_define_name,  $index, 1;
							splice @valid_define_value, $index, 1;
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
				$result = is_valid_define_name($1);
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
				$result = is_valid_define_name($1);
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
						print "numeric! $result\n";
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
					die "#error in valid line!\n";
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
		&output_line($local_line);
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


sub line_parse
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



#/* マクロ定義の一覧表示 */
sub print_defines
{
	my $index;
	for ($index = 0; $index < @valid_define_name; $index++)
	{
		print "define[$index] $valid_define_name[$index] : $valid_define_value[$index]\n";
	}

	for ($index = 0; $index < @literals; $index++)
	{
		print "literals[$index] : $literals[$index]\n";
	}
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
		$result = is_valid_define_name($1);
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
	$text = replace_define($text);
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

	#/* インクルードとプラグマ以外のディレクティブは無視 */
	if ($local_line =~ /^\#/)
	{
#		print "ignore directive \#$'\n";
		return;
	}

	#/* 1行で完結しているtypedef */
	if ($local_line =~ /^\s*typedef\s+([^;]*;)/)
	{
		my $defs = $1;
		my $existing_types = "";
		my $defined_type = "";

		#/* 末尾のスペースを除去 */
		$defs =~ s/([^\s]*)\s+;/$1;/g;
#		print "ignore typedef $defs\n";

		while ($defs =~ /([_A-Za-z][_A-Za-z0-9]*)\s+([^;]*;)/)
		{
			$defs = $2;
			$existing_types = $existing_types . " " . $1;
#			print "existing_types : $existing_types, $defs\n";
		}

		$defined_type = substr($defs, 0, length($defs) -1);

#		print "typedef $existing_types as $defined_type!\n";
		return;
	}

	#/* 型定義の中身は無視する */
	if ($type_define == 1)
	{
		#/* typedefの終了行 */
		if ($local_line =~ /^[^ ].*;\n/)
		{
#			print "type define end! $local_line";
			$type_define = 0;
		}
		return;
	}

	#/* enumやstructのtypedef開始行 */
	if ($local_line =~ /^\s*typedef/)
	{
#		print "type define start! $local_line";
		$type_define = 1;
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
			if ($1 =~ /^static/)
			{
				$current_sentence->static(1);
			}
			elsif ($1 =~ /^const/)
			{
				$current_sentence->const(1);
			}
			elsif ($1 =~ /^extern/)
			{
				$current_sentence->extern(1);
			}
			elsif ($1 =~ /(^struct|^union|^enum)/)
			{
#				print "$1\n";
				$current_sentence->struct(1);
			}
			elsif ($1 =~ /(^inline|^volatile|^auto|^signed)/)
			{
				#/* 解析対象外 */
#				print "$1\n";
			}
			elsif ($1 =~ /^unsigned/)
			{
				$current_sentence->unsigned(1);
			}
			elsif ($1 =~ /(^void|^char|^int|^short|^long|^float|^double)/)
			{
#				print "$1\n";
			}
			elsif ($1 =~ /(^if|^for|^else|^while|^do|^switch|^case|^break|^continue|^return|^goto)/)
			{
				#/* 制御文。これらは{};:の文の区切りまでに一つしか入らないはず */
#				print "$1\n";
				$current_sentence->control($1);
			}
			elsif ($1 =~ /(^sizeof)/)
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
		elsif ($remaining_line =~ /^([\+\-]*[0-9\.][0-9e\.]+[fFlL]*)/)
		{
			#/* 浮動小数（C99では16進表記も可能だそうですが、ここでは無視、この正規表現も怪しいが、コンパイル通るコードなら大丈夫なはず） */
			print "float $1\n";
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
		elsif ($remaining_line =~ /^([1-9][0-9]*[uUlL]*)/)
		{
			#/* 10進数 */
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
		elsif ($remaining_line =~ /^(\+\+|\-\-|\!|\~|\&|\*)/)
		{
			#/* 単項演算子 */
#			print "Unary operator! $1\n";
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
	$current_sentence->init("");
	$current_sentence->extern(0);
	$current_sentence->static(0);
	$current_sentence->const(0);
	$current_sentence->unsigned(0);
	$current_sentence->control(0);
	$current_sentence->struct(0);
	$current_sentence->array(0);
	$current_sentence->position(0);
	$current_sentence->astarisk(0);
	$current_sentence->init_nest(0);
	$current_sentence->temp("");
	$current_sentence->is_func(0);

	$current_sentence->clear(0);
	$current_sentence->new_path("");
	$current_sentence->backward("");
	$current_sentence->switch_val("");
	$current_sentence->pu_text("");
	$current_sentence->case_val("");
	$current_sentence->func_call(0);
	$current_sentence->case_condition("");
	$current_sentence->pop_current_path(0);

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



#/* グローバルスコープの１行解析 */
sub analyze_global_line
{
	my $loop;
	my @local_array = @{$current_sentence->words};

	$current_sentence->clear(1);

#	&disp_current_words();
	for ($loop = $current_sentence->position; $loop < @local_array; $loop++)
	{
#		print "analyze : $local_array[$loop]\n";
		if ($local_array[$loop] =~ /^(struct|union|enum)$/)
		{
			#/* グローバルスコープでこれらのキーワードが出てきた場合、typedefを除き、*/
			#/* ①型の定義(無名の型もありうる)                                       */
			#/* ②型定義＋変数／関数の宣言                                           */
			#/* ③定義済みの型による変数／関数の宣言                                 */
			#/* のいずれか                                                           */
			print "analyze : $local_array[$loop] in global\n";
			if ($loop+1 == @local_array)
			{
				print "$1 without name!\n";
				$current_sentence->typ("$1 \(no name\)");

				#/* 後続行に処理を継続 */
				$current_sentence->clear(0);
				$current_sentence->position($loop + 1);
				$global_data->bracket_type($local_array[$loop]);
				last;
			}
			else
			{
				print "$1 $local_array[$loop+1]\n";
				if ($loop+2 == @local_array)
				{
					#/* 名称までで改行していた場合は、型定義が始まる */
					print "$1 $local_array[$loop+1] define\n";
					$current_sentence->typ("$1 $local_array[$loop+1]");

					#/* 後続行に処理を継続 */
					$current_sentence->clear(0);
					$current_sentence->position($loop + 2);
					$global_data->bracket_type($local_array[$loop]);
					last;
				}
				else
				{
					#/* 名称の続きがあるとしたら、変数か関数の宣言が続く */
					if ($local_array[$loop+2] eq "*")
					{
						$current_sentence->typ("$1 $local_array[$loop+1]*");
						$loop++;
					}
					else
					{
						$current_sentence->typ("$1 $local_array[$loop+1]");
					}

					#/* 関数または変数の名称 */
					$current_sentence->name("$local_array[$loop+2]");

					if ($local_array[$loop+3] eq ";")
					{
#						print "struct variable imp!!!!!!!!!! $local_array[$loop+2]\n";
						last;
					}
					elsif ($local_array[$loop+3] eq "=")
					{
#						print "struct variable imp with init val!!!!!!!!!! $local_array[$loop+2]\n";

						#/* 後続行に処理を継続 */
						$current_sentence->clear(0);
						$current_sentence->position($loop + 4);
						last;
					}
					elsif ($local_array[$loop+3] eq "(")
					{
						printf "new func1\n";
						&new_function($current_sentence->name, $current_sentence->typ);
						&analyze_arg_list($loop+4);
						last;
					}
				}
				
				last;
			}
		}
		elsif ($local_array[$loop] eq "typedef")
		{
			$loop = &analyze_typedef($loop);
		}
		elsif ($local_array[$loop] =~ /^(static|extern|inline|const|volatile|unsigned|signed|auto)$/)
		{
			#/* 型の修飾子 */
			#/* すでに前段で処理しているのでここではスルー */
		}
		elsif ($local_array[$loop] =~ /^(void|char|int|short|long|float|double)$/)
		{
			#/* 標準の型 */
			if ($global_data->bracket_type eq "none")
			{
#				print "type : $1\n";
				$current_sentence->typ("$1");
			}
		}
		elsif ($local_array[$loop] =~ /(\[)/)
		{
			#/* []開く 配列の定義 */
			$current_sentence->array(1);
			if ($current_sentence->name eq "")
			{
				$current_sentence->name($current_sentence->typ);
				$current_sentence->typ("int");
			}

			while ($local_array[$loop] ne "]")
			{
				$current_sentence->temp($current_sentence->temp . "$local_array[$loop]");
				$loop++;
			}

			$current_sentence->temp($current_sentence->temp . "]");
		}
		elsif ($local_array[$loop] =~ /(\{)/)
		{
			#/* 関数外で{}が現れるのは、配列・構造体の定義か初期化 */
#			printf "{ in global $in_define, $indent_level, $loop, @local_array, init_nest=%d\n", $current_sentence->init_nest;
			if ($global_data->bracket_type ne "none")
			{
				#/* 定義の場合は{}のネストを調べる */
				$global_data->indent($global_data->indent + 1);
			}

			if ($loop + 1 == @local_array)
			{
				#/* 初期値の場合は、後続行に処理を継続 */
#				print "{ in global!!!!\n";
				$current_sentence->clear(0);
				$current_sentence->position($loop + 1);
				$current_sentence->init_nest($current_sentence->init_nest + 1);
				last;
			}
		}
		elsif ($local_array[$loop] =~ /(\})/)
		{
			#/* 関数外で{}が現れるのは、配列・構造体の定義か初期化 */
#			my $num = @local_array;
#			printf "} in global $in_define, $indent_level, $loop, %d, init_nest=%d\n", $num, $current_sentence->init_nest;
			if ($global_data->bracket_type ne "none")
			{
				#/* 定義の場合は{}のネストを調べる */
				$global_data->indent($global_data->indent - 1);
				if ($global_data->indent == 0)
				{
					#/* 構造体定義の末尾 */
					$global_data->bracket_type("none");
				}
			}

			if ($loop + 1 == @local_array)
			{
				#/* 初期値の場合は後続行に処理を継続 */
#				printf "} in global!!!!\n";
				$current_sentence->clear(0);
				$current_sentence->position($loop + 1);
				$current_sentence->init_nest($current_sentence->init_nest - 1);
				last;
			}
		}
		elsif ($local_array[$loop] =~ /(\()/)
		{
			#/* ()開く */
			printf "$1 in global! in_define = %d, init_nest = %d\n", $global_data->bracket_type, $current_sentence->init_nest;
			if ( ($global_data->bracket_type ne "none") ||
			     ($current_sentence->init_nest > 0) )
			{
				$loop++;
				while ($loop < @local_array)
				{
					if ($local_array[$loop] eq ")")
					{
#						print "endof ()!\n";
					}

					$loop++;
				}

				if ($loop == @local_array)
				{
					#/* 後続行に処理を継続 */
					$current_sentence->clear(0);
					$current_sentence->position($loop);
					last;
				}
			}
			elsif ($current_sentence->name eq "")
			{
				if ($local_array[$loop+1] =~ /(\*+)/)
				{
					my $count = 0;
					while($local_array[$loop+1] =~ /(\*+)/)
					{
						#/* アスタリスクが重なる場合 */
						$loop++;
						$count++;
					}

					#/* 名前が未定義で ( の後に * がくる場合は関数ポインタの可能性あり */
					print "func ptr $1\n";

					if ($current_sentence->typ eq "")
					{
						#/* 型名省略の場合 */
						$current_sentence->typ("int");
					}

					my $astarisk = "*" x $count;
					$current_sentence->name($local_array[$loop+1]);
					if ($local_array[$loop+2] eq "(")
					{
						#/* 関数または関数ポインタ型を返す関数 */
						print "may be function return func_ptr!\n";
						$loop = &analyze_arg_list($loop+3);

						if ($local_array[$loop + 1] ne ")")
						{
							die "strange function declare!\n";
						}

						if ( ($loop + 2 >= @local_array) || ($local_array[$loop + 2] ne "(") )
						{
							$loop += 1;

							#/* 引数リストが来ないということは、紛らわしい関数定義 */
							$current_sentence->temp($current_sentence->temp . "$astarisk");
						}
						else
						{
							$loop += 2;
							$current_sentence->temp($current_sentence->temp . "($astarisk)");
							while ($local_array[$loop] ne ")")
							{
								print "function return func_ptr!!!!!!! arg $local_array[$loop]\n";
								$current_sentence->temp($current_sentence->temp . " " . "$local_array[$loop]");
								$loop++;
							}

							$current_sentence->temp($current_sentence->temp . ")");
							
							my $temp_text = $current_sentence->temp;

							print "function return func_ptr!!!!!!!  $temp_text\n";
						}

						printf "new func2\n";
						&new_function($current_sentence->name, $current_sentence->typ);
						$global_data->in_function(1);
						$current_sentence->is_func(1);
					}
					else
					{
						#/* 通常の変数または関数ポインタの定義 */
						if ($local_array[$loop+2] ne ")")
						{
							die "invalid function pointer declare1?\n";
						}

						if ($local_array[$loop+3] ne "(")
						{
							#/* 引数リストが来ないということは、紛らわしい変数定義 */
							$current_sentence->temp($current_sentence->temp . "($astarisk)");
							$loop += 2;
						}
						else
						{
							#/* ここまで来たら関数ポインタ */
							print "func_ptr!!!!!!!  $local_array[$loop+1]\n";
							$current_sentence->temp($current_sentence->temp . "($astarisk)");
							$loop += 3;
							while ($local_array[$loop] ne ")")
							{
								$current_sentence->temp($current_sentence->temp . " " . "$local_array[$loop]");
								$loop++;
							}

							$current_sentence->temp($current_sentence->temp . ")");
						}
					}
				}
				else
				{
					if ($current_sentence->typ eq "")
					{
						die "invalid function declare?\n";
					}
					else
					{
						$current_sentence->name($current_sentence->typ);
						$current_sentence->typ("int");
					}

					#/* 名前が定義済みの場合は関数とみなす */
					printf "new func3\n";
					&new_function($current_sentence->name, $current_sentence->typ);
					$loop = &analyze_arg_list($loop+1);
					$global_data->in_function(1);
					$current_sentence->is_func(1);
				}
			}
			else
			{
				#/* 名前が定義済みの場合は関数とみなす */
				printf "new func4\n";
				&new_function($current_sentence->name, $current_sentence->typ);
				$loop = &analyze_arg_list($loop+1);
				$global_data->in_function(1);
				$current_sentence->is_func(1);
			}
		}
		elsif ($local_array[$loop] =~ /(\;)/)
		{
			#/* セミコロン */
			if ($global_data->bracket_type ne "none")
			{
				#/* 型定義の中のセミコロンは無視 */
				if ($loop + 1 == @local_array)
				{
					#/* 初期値の場合は後続行に処理を継続 */
					$current_sentence->clear(0);
					$current_sentence->position($loop + 1);
					last;
				}
			}
			elsif ($current_sentence->is_func == 1)
			{
				#/* 関数の場合、宣言だけが行われているので関数には入らない。 */
				print "function declare!\n";
				$global_data->in_function(0);
			}
			elsif ($current_sentence->typ eq "")
			{
				#/* 空の文 */
				print "empty sentence!\n";
			}
			elsif ($current_sentence->name eq "")
			{
				#/* 型の定義のみ */
				print "only struct/union/enum define!\n";
			}
			else
			{
				#/* 変数の宣言 */
#				print "new Val1!  [$local_array[$loop]] $loop, @local_array\n";
				my $new_variable = &create_new_variable();
			}
		}
		elsif ($local_array[$loop] =~ /(\,)/)
		{
			#/* カンマ */
#			printf "init_nest == %d\n", $current_sentence->init_nest;
			if ($current_sentence->init_nest == 0)
			{
				if ($current_sentence->name eq "")
				{
					#/* typだけ設定されていて、nameが空の場合は、型を省略したとみなす */
					$current_sentence->name($current_sentence->typ);
					$current_sentence->typ("int");
				}

				if ($current_sentence->is_func == 1)
				{
					#/* 関数の場合、宣言だけが行われているので関数には入らない。 */
					print "function declare!\n";
					$global_data->in_function(0);
				}
				else
				{
					print "new Val2!  [$local_array[$loop]] \n";
					my $new_variable = &create_new_variable();
				}
				$current_sentence->is_func(0);
				$current_sentence->temp("");
				$current_sentence->astarisk(0);
				$current_sentence->init("");
				$current_sentence->array(0);
				$current_sentence->name("");
			}
			else
			{
				if ($loop + 1 == @local_array)
				{
					#/* 後続行に処理を継続 */
					$current_sentence->clear(0);
					$current_sentence->position($loop + 1);
					last;
				}
			}
		}
		elsif ($local_array[$loop] eq "=")
		{
			#/* イコール */
			$loop = &analyze_equal($loop);
		}
		elsif ($local_array[$loop] =~ /(\*+)/)
		{
			#/* アスタリスク */
#			print "astarisk  $1\n";
			if ($current_sentence->typ eq "")
			{
				#/* 型名が省略されているとみなす */
				$current_sentence->typ("int");
			}

			#/* アスタリスクは重なる場合があるので、length分加算する。int*** a_ptr; みたいな */
			$current_sentence->astarisk($current_sentence->astarisk + length($local_array[$loop]));
		}
		elsif ($local_array[$loop] =~ /([_A-Za-z][_A-Za-z0-9]*)/)
		{
			#/* シンボル */
#			print "symbol!  [$1]\n";
			my $symbol = $1;
			if ($global_data->bracket_type ne "none")
			{
				if ($loop + 1 == @local_array)
				{
					#/* 後続行に処理を継続 */
					$current_sentence->clear(0);
					$current_sentence->position($loop + 1);
					last;
				}
			}
			elsif ($current_sentence->init_nest > 0)
			{
				#/* 後続行に処理を継続 */
				$current_sentence->clear(0);
				$current_sentence->position($loop + 1);
				last;
			}
			elsif ($current_sentence->typ eq "")
			{
				#/* 型指定とみなす */
				$current_sentence->typ($symbol);
			}
			else
			{
				#/* 型がすでに決定している場合は、変数／関数名とみなす */
				if ($current_sentence->name eq "")
				{
					$current_sentence->name($symbol);
				}
				else
				{
#					die "already name defined!\n";
				}
			}
		}
		else
		{
			#/* 配列、構造体の初期化中 */
#			printf "unknown!!!!! $local_array[$loop], init_nest = %d\n" , $current_sentence->init_nest;
			if ($current_sentence->init_nest > 0)
			{
				if ($loop + 1 == @local_array)
				{
					#/* 後続行に処理を継続 */
					$current_sentence->clear(0);
					$current_sentence->position($loop + 1);
					last;
				}
			}
			else
			{
				print "unknown!!!!! $local_array[$loop] @local_array\n";
			}
		}
	}

	if ($current_sentence->clear == 1)
	{
		&clear_current_sentence();
	}
}


#/* 親パスに復帰させる */
sub pop_path
{
	$current_path = $current_path->parent;
	pop @path_stack;
}

sub new_path
{
	my $function = $_[0];
	my $parent   = $_[1];
	my $indent   = $_[2];
	my $temp_path;
	my $ret_val = 0;
#	print "new_path @ $indent\n";


	$temp_path = Path->new();
	$temp_path->function($function);
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
		print "add *!\n";
		$typ = $typ . "*";
		$astarisk--;
	}

	#/* 関数ポインタや配列の場合に備えて、型名にtempを付加する */
	$typ = $typ . $current_sentence->temp;

	print "new function! [ $typ ][ $name ]\n";
	$current_function = Functions->new();
	$current_function->name($name);
	$current_function->ret_typ($typ);
	$current_function->lines(1);
	$current_function->comment(0);
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
	@{$current_function->local_type} = ();

	&new_path($current_function, "", 0);
	$current_function->path($current_path);
}



#/* 関数の引数解析処理(戻り値は引数リストを閉じる)のインデックス) */
sub analyze_arg_list
{
	my @local_array = @{$current_sentence->words};
	my $loop = $_[0];
	my $temp1 = "";
	my $temp2 = "";
	my $astarisk = 0;
	my $is_struct = "";

	while($loop + 1 < @local_array)
	{
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
		elsif ($local_array[$loop] =~ /(struct|union|enum)/)
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


#/* 新規変数の登録 */
sub create_new_variable
{
	my $name = $current_sentence->name;
	my $init = $current_sentence->init;
	my $astarisk = $current_sentence->astarisk;

	my $new_variable = Variables->new();
	$new_variable->name($current_sentence->name);
	$new_variable->typ($current_sentence->typ);
	while ($astarisk > 0)
	{
		print "add *!\n";
		$new_variable->typ($new_variable->typ . "*");
		$astarisk--;
	}

	#/* 関数ポインタや配列の場合に備えて、型名にtempを付加する */
	$new_variable->typ($new_variable->typ . $current_sentence->temp);

	$new_variable->init($current_sentence->init);
	$new_variable->extern($current_sentence->extern);
	$new_variable->static($current_sentence->static);
	$new_variable->const($current_sentence->const);
	$new_variable->array($current_sentence->array);

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

	my $typ = $new_variable->typ;
	print "new Variable! [ $typ ] [ $name ] = [ $init ]\n";
	push @variables, $new_variable;
	return $new_variable;
}


#/* 特に解析対象とならないようなワードの追加 */
sub add_free_word
{
	my $add_word = $_[0];

	if ($current_sentence->pu_text eq "")
	{
		$current_sentence->pu_text(":" . $add_word);
	}
	else
	{
		$current_sentence->pu_text($current_sentence->pu_text . " " . $add_word);
	}
}


#/* ( の解析                                     */
#/* 関数内では以下のパターンを判別する必要がある */
#/* 1. 演算の()         */
#/* 2. キャストの()     */
#/* 3. 関数コールの()   */
#/* 4. 関数ポインタの() */
sub analyze_round_bracket_open
{
	my $loop        = $_[0];
	my @local_array = @{$current_sentence->words};

	if ($prev_word =~ /([_A-Za-z][_A-Za-z0-9]*)/)
	{
		#/* 前の語がシンボルだった場合 */
		my $symbol = $1;

		if ($symbol ne "sizeof")
		{
			print "function call! $symbol()\n";
			&add_function_call($symbol);
			$current_sentence->func_call(1);
		}
	}

	#/* 解析対象外のワード */
	&add_free_word("(");
	return $loop;
}

sub analyze_round_bracket_close
{
	my $loop        = $_[0];
	my @local_array = @{$current_sentence->words};

	#/* 解析対象外のワード */
	&add_free_word($local_array[$loop]);
	return $loop;
}


sub analyze_if
{
	my $bracket_level = 0;
	my $loop        = $_[0];
	my @local_array = @{$current_sentence->words};

	#/* if文の処理 */
	if ($local_array[$loop+1] ne "(")
	{
		#/* ifの後に()が来ない。マクロ使っているやつ */
		print "strange if sentence!\n";
		$current_sentence->pu_text($local_array[$loop+1]);
	}
	else
	{
		$bracket_level = 1;
	}

	$loop += 2;
	while ($bracket_level > 0)
	{
		if ($local_array[$loop] eq "(")
		{
			$bracket_level++;
		}
		elsif ($local_array[$loop] eq ")")
		{
			$bracket_level--;
		}

		if ($bracket_level > 0)
		{
			$current_sentence->pu_text($current_sentence->pu_text . $local_array[$loop]);
		}

		$loop++;
	}

	if ($prev_word eq "else")
	{
		#/* else文の直後にifの場合は : 最後に追加されているであろうelse (No)をpopしてしまう */
		pop @{$current_path->pu_text};
		$current_sentence->pu_text("elseif (" . $current_sentence->pu_text . ") then (Yes)\n");
	}
	else
	{
		$current_sentence->pu_text("if (" . $current_sentence->pu_text . ") then (Yes)\n");
	}

#	printf "pu_text1 : %s\n", $current_sentence->pu_text;
	$current_sentence->new_path("if");
	return $loop;
}

sub analyze_do
{
	my $loop        = $_[0];
	my @local_array = @{$current_sentence->words};

	$current_sentence->new_path("do");
	&push_pu_text("partition \"do while loop\" {\n");
	&push_pu_text("repeat\n");
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
#	&push_pu_text("->goto **$label**;\n");
#	&push_pu_text("($label_num)\n");
	&push_pu_text("$color:goto **$label**;\n");
	&push_pu_text("detach\n");
	$loop += 1;

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
	$loop++;

	if ($break_mode eq "loop")
	{
		#/* ループ処理中であれば、ループの終了 */
		$current_sentence->pu_text("break\n");
	}
	else
	{
		#/* ループ処理でなければ、switch ～ case文の終了 */
		if ( ($current_path->type eq "case") ||
		     ($current_path->type eq "default") )
		{
			#/* 残念ながら、if elseの両方でbreakした場合などは、拾えません */
			$current_path->break(1);
#			&push_pu_text(":break}\n");				#/* これは冗長に見えるので入れない */
		}
	}

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
		&push_pu_text(":return value : $ret_val]\n");
#		print "return! value : $ret_val\n";
	}
	else
	{
#		print "no value return!\n";
	}

	&push_pu_text("stop\n");
	$current_path->break(1);
	$force_prev_word = "return";

	return $loop;
}


sub analyze_switch
{
	my $bracket_level = 0;
	my $loop        = $_[0];
	my @local_array = @{$current_sentence->words};

	#/* switch文 */
	if ($local_array[$loop+1] ne "(")
	{
		#/* switchの後に()が来ない。マクロ使っているやつ */
		print "strange if sentence!\n";
		$current_sentence->pu_text($local_array[$loop+1]);
	}
	else
	{
		$bracket_level = 1;
	}

	$loop += 2;
	while ($bracket_level > 0)
	{
		if ($local_array[$loop] eq "(")
		{
			$bracket_level++;
		}
		elsif ($local_array[$loop] eq ")")
		{
			$bracket_level--;
		}

		if ($bracket_level > 0)
		{
			$current_sentence->pu_text($current_sentence->pu_text . $local_array[$loop]);
		}

		$loop++;
	}

	$current_sentence->switch_val("(" . $current_sentence->pu_text . ")");
	$current_sentence->pu_text("");
	&push_pu_text("partition \"switch - case\" {\n");
	$current_sentence->new_path("switch");
	printf "switch : %s\n", $current_sentence->switch_val;
	return $loop;
}


sub analyze_for
{
	my $loop        = $_[0];
	my @local_array = @{$current_sentence->words};

	#/* for文 */
	my $init_condition;
	my $repeat_condition;
	my $pre_repeat_exec;

	#/* 初期化条件 */
	$init_condition = $local_array[$loop + 2];
	$loop += 3;
	while ($local_array[$loop] ne ";")
	{
		$init_condition = $init_condition . $local_array[$loop];
		$loop++;
	}
	$init_condition = $init_condition . $local_array[$loop];


	#/* 実行条件 */
	$repeat_condition = $local_array[$loop + 1];
	$loop += 2;
	while ($local_array[$loop] ne ";")
	{
		$repeat_condition = $repeat_condition . $local_array[$loop];
		$loop++;
	}


	#/* 繰り返し処理 */
	$pre_repeat_exec = $local_array[$loop + 1];
	$loop += 2;
	while ($local_array[$loop] ne ")")
	{
		$pre_repeat_exec = $pre_repeat_exec . $local_array[$loop];
		$loop++;
	}
	$pre_repeat_exec = $pre_repeat_exec . ";";
	print "for ($init_condition  $repeat_condition  $pre_repeat_exec)\n";

	&push_pu_text("partition \"for loop\" {\n");
	&push_pu_text(":$init_condition]\nwhile ($repeat_condition) is (Yes)\n");
	$current_sentence->new_path("for");
	$current_sentence->backward($pre_repeat_exec);
	return $loop;
}


sub analyze_while
{
	my $bracket_level = 0;
	my $loop        = $_[0];
	my @local_array = @{$current_sentence->words};

	#/* while文 */
	if ($local_array[$loop+1] ne "(")
	{
		#/* whileの後に()が来ない。マクロ使っているやつ */
		print "strange while sentence!\n";
		$current_sentence->pu_text($local_array[$loop+1]);
	}
	else
	{
		$bracket_level = 1;
	}

	$loop += 2;
	while ($bracket_level > 0)
	{
		if ($local_array[$loop] eq "(")
		{
			$bracket_level++;
		}
		elsif ($local_array[$loop] eq ")")
		{
			$bracket_level--;
		}

		if ($bracket_level > 0)
		{
			$current_sentence->pu_text($current_sentence->pu_text . $local_array[$loop]);
		}

		$loop++;
	}

	if ($prev_word eq "do")
	{
		$current_sentence->pu_text("repeat while (" . $current_sentence->pu_text . ") is (Yes) not (No)\n}\n");
	}
	else
	{
		&push_pu_text("partition \"while loop\" {\n");
		$current_sentence->pu_text("while (" . $current_sentence->pu_text . ") is (Yes)\n");
		print "pu_text4 : " . $current_sentence->pu_text;
		$current_sentence->new_path("while");
	}

	return $loop;
}


sub analyze_else
{
	my $loop        = $_[0];
	my @local_array = @{$current_sentence->words};

	#/* else文 */
	if ( ($loop + 1 >= @local_array) ||
	     ($local_array[$loop + 1] ne "if") )
	{
		#/* else文の処理 : 最後に追加されているであろうendifをpopしてしまう */
		my $poped = pop @{$current_path->pu_text};
		$current_sentence->pu_text("else (No)\n");
#		printf("pu_text2 : else (No),  poped : %s\n", $poped);
		$current_sentence->new_path("else");
	}
	else
	{
		print "else if!!!\n";
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
			if ( ($prev_word ne "case") &&
			     ($prev_word ne "default") )
			{
				#/* 何かしら処理を行ってからfall throughしてくるケース */
				&push_pu_text(":fall through}\n");
				&push_pu_text("detach\n");
			}
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

		$current_sentence->new_path("default");
		$current_sentence->case_condition("if (switch $switch_val) then (default)\n");
	}
	else
	{
		if ($prev_word ne "case")
		{
			$current_sentence->new_path("default");
			$current_sentence->case_condition("elseif () then (default)\n");
		}
		else
		{
			#/* caseからfall throughでdefaultにつながっている場合、まず直前の子パスに戻る */
			print "case fall through to default!\n";
			&re_enter_latest_child();

			#/* それから直前のif条件をpopしてしまって、条件を書き換える */
			pop @{$current_path->pu_text};
			$current_path->type("default");
			$current_sentence->pu_text("elseif () then (default)\n");
		}
	}

	$force_prev_word = "default";
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
			if ( ($prev_word ne "case") &&
			     ($prev_word ne "default") )
			{
				#/* 何かしら処理を行ってからfall throughしてくるケース */
				&push_pu_text(":fall through}\n");
				&push_pu_text("detach\n");
			}
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
		printf "add case value : %s\n", $current_sentence->case_val;
	}
	

	$current_path->case_count($current_path->case_count + 1);
	printf "case : %s", $current_sentence->case_val;

	if ($current_path->case_count <= 0)
	{
		die "strange switch case sentence!!!\n";
	}
	elsif ($current_path->case_count == 1)
	{
		#/* 最初のcase文 */
		my $case_text = "if (switch $switch_val) then (case " . $current_sentence->case_val . ")";
		$current_sentence->new_path("case");
		$force_prev_word = "case";
		$current_sentence->case_condition($case_text);
	}
	else
	{
		#/* 2個目以降のcase文 */
		if ( ($prev_word ne "case") &&
		     ($prev_word ne "default") )
		{
			my $case_text = "elseif () then (case " . $current_sentence->case_val . ")";
			$current_sentence->new_path("case");
			$force_prev_word = "case";
			$current_sentence->case_condition($case_text);
		}
		else
		{
			my $loop;
			my $is_first;

			$is_first = (@{$current_path->child} == 1);

			#/* 複数caseがfall throughでつながっている場合、まず直前の子パスに戻る */
			&re_enter_latest_child();
			push @{$current_path->case_val}, $current_sentence->case_val;

			#/* それから直前のif条件をpopしてしまって、条件を書き換える */
			pop @{$current_path->pu_text};

			if ($current_path->type eq "default")
			{
				if ($is_first)
				{
					#/* 先頭のラベルにはswitch条件を記述しておく */
					$current_sentence->case_condition("if (switch $switch_val) then (default)\n");
				}
				else
				{
					$current_sentence->case_condition("elseif () then (default)\n");
				}
			}
			else
			{
				if ($is_first)
				{
					#/* 先頭のラベルにはswitch条件を記述しておく */
					$current_sentence->case_condition("if (switch $switch_val) then (");
				}
				else
				{
					$current_sentence->case_condition("elseif () then (");
				}

				for ($loop = 0; $loop < @{$current_path->case_val}; $loop++)
				{
					$current_sentence->case_val($current_path->case_val($loop));
#					printf "foreach case_val : %s from $current_path $current_path->case_val\n", $current_sentence->case_val;
					$current_sentence->case_condition($current_sentence->case_condition . "case " . $current_sentence->case_val);
					if ($loop < @{$current_path->case_val} - 1)
					{
						$current_sentence->case_condition($current_sentence->case_condition . ", ");
					}
				}

				$current_sentence->case_condition($current_sentence->case_condition . ")\n");
			}

			printf "case : %s", $current_sentence->case_condition;
			$current_sentence->pu_text($current_sentence->case_condition);
		}
	}

	return $loop;
}

sub analyze_typedef
{
	my $loop        = $_[0];
	my @local_array = @{$current_sentence->words};
	my $existing_type = "";
	my $defined_type  = "";

	if ($loop + 1 >= @local_array)
	{
		die "strange type define!!!\n";
	}

	$loop++;
	if ($local_array[$loop] =~ /^(struct|union|enum)$/)
	{
		$global_data->bracket_type("typedef");
	}
	elsif ($local_array[@local_array - 1] ne ";")
	{
		die "strange type define!!!\n";
	}
	else
	{
		$defined_type = $local_array[@local_array - 2];
		while ($loop < (@local_array - 2))
		{
			$existing_type = $existing_type . $local_array[$loop];
			$loop++;
		}
	}

	return $loop;
}

sub analyze_square_bracket_open
{
	my $loop        = $_[0];
	my @local_array = @{$current_sentence->words};

	&add_free_word($local_array[$loop]);
	return $loop;
}

sub analyze_square_bracket_close
{
	my $loop        = $_[0];
	my @local_array = @{$current_sentence->words};

	&add_free_word($local_array[$loop]);
	return $loop;
}

sub analyze_equal
{
	my $loop        = $_[0];
	my @local_array = @{$current_sentence->words};

	if ($global_data->in_function == 1)
	{
		&add_free_word($local_array[$loop]);
	}
	else
	{
		#/* イコール */
		if ($current_sentence->name eq "")
		{
			#/* typだけ設定されていて、nameが空の場合は、型を省略したとみなす */
			$current_sentence->name($current_sentence->typ);
			$current_sentence->typ("int");
		}

		#/* 型と名前がそろっている */
		if ($loop + 1 == @local_array)
		{
			#/* 同一行に初期値が書かれていない場合 */
#			print "equal!!!! with out init value in this line! \n";

			#/* 後続行に処理を継続 */
			$current_sentence->clear(0);
			$current_sentence->position($loop + 1);
			last;
		}
		else
		{
			#/* 同一行に初期値が書かれている場合 */
#			print "equal!!!! [$local_array[$loop + 1]] \n";
			while ($local_array[$loop + 1] =~ /[^\;\,]/)
			{
				$current_sentence->init($current_sentence->init . $local_array[$loop + 1]);
				$loop++;
			}
		}
	}
	return $loop;
}

sub analyze_colon
{
	my $loop        = $_[0];
	my @local_array = @{$current_sentence->words};

	print "label define!!!!! $prev_word:\n";

	if ($prev_word =~ /[^_A-Za-z0-9]/)
	{
		die "strange label define!!! [$prev_word]\n";
	}

	my $label_num = &add_array_no_duplicate($current_function->label ,$prev_word);
	my $color = &get_color_text($label_num);
	&push_pu_text("$color:**$prev_word**;\n");
	$current_sentence->pu_text("");
	$current_path->break(0);   #/* ラベルが貼られると、到達不可能コードではなくなる */

	return $loop;
}


sub analyze_semicolon
{
	my $loop        = $_[0];
	my @local_array = @{$current_sentence->words};

	#/* セミコロン */
	if ($current_path->indent == $global_data->indent)
	{
		my $path_type = $current_path->type;
		if ( ($path_type ne "case") &&
		     ($path_type ne "default") )
		{
			print "$path_type path without {}! @ " . $global_data->indent . " \n";

			#/* 親の実行PATHに復帰する */
			$current_sentence->pop_current_path(1);
		}
	}

	if ($current_sentence->pu_text ne "")
	{
		$current_sentence->pu_text($current_sentence->pu_text . " " . $local_array[$loop]);
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
		$global_data->in_function(0);
		push @{$current_function->texts}, $current_sentence->text;
		push @{$current_path->texts}, $current_sentence->text;
		push @functions, $current_function;

		if ($prev_word ne "return")
		{
#			print "without return!!!!\n";
			&push_pu_text("stop\n");
		}
		else
		{

		}
	}
	elsif ($current_path->indent == $global_data->indent)
	{
		#/* 親の実行PATHに復帰する */
		&return_parent_path();
#		printf "pu_text10 : %s\n", $current_sentence->pu_text;
	}
	elsif ($current_path->indent > $global_data->indent)
	{
		my $path_type = $current_path->type;
		&pop_path();

		#/* ここに来るのはswitch ～ case文のみ */
		if ( ($path_type eq "case") ||
		     ($path_type eq "default") )
		{
			print "return from switch!\n";
			$current_sentence->pu_text("endif\n}\n");

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
		printf "current_path->type = %s\n", $current_path->type;
		printf "current_path->indent = %d\n", $current_path->indent;
		printf "indent_level = " . $global_data->indent . "\n";
	}
	return $loop;
}

sub analyze_ternary
{
	my $loop        = $_[0];
	my @local_array = @{$current_sentence->words};

	#/* 三項演算子 */
	#/* とりあえず、行末まで全部一つの処理として扱う */
	while ($loop < @local_array)
	{
		&add_free_word($local_array[$loop]);
		$loop++;
	}

#	print "Ternary operator! [" . $current_sentence->pu_text . "]\n";

	return $loop;
}


#/* 関数スコープの中の１行解析 */
sub analyze_function_line
{
	my $loop;
	my @local_array = @{$current_sentence->words};
	$current_sentence->clear(1);

#	&disp_current_words();
	for ($loop = $current_sentence->position; $loop < @local_array; $loop++)
	{
#		print "analyze in func : $local_array[$loop]\n";
		if (exists $analyze_funcs{$local_array[$loop]}) {
			print "analyze func $local_array[$loop] hit!!!\n";
			my $func = $analyze_funcs{$local_array[$loop]};
			$loop = &$func($loop);
		}
		elsif ($local_array[$loop] =~ /^(static|extern|inline|const|volatile|unsigned|signed|auto)$/)
		{
			#/* 修飾子 */
			print "modifier! $local_array[$loop]\n";
#			$pu_text = &add_modifier($pu_text, \@local_array, \$loop);
		}
		else
		{
			#/* 解析対象外のワード */
			&add_free_word($local_array[$loop]);
		}

		#/* ワードを覚えておく */
		if ($force_prev_word ne "")
		{
			$prev_word = $force_prev_word;
			$force_prev_word = "";
		}
		else
		{
			$prev_word = $local_array[$loop];
		}
	}

	if ($current_sentence->clear == 1)
	{
		if ($global_data->in_function == 1)
		{
			push @{$current_function->texts}, $current_sentence->text;
			push @{$current_path->texts}, $current_sentence->text;

			if ($current_sentence->pu_text =~ /^\:/)
			{
				if ($current_sentence->func_call == 0)
				{
					$current_sentence->pu_text($current_sentence->pu_text . "]\n");
				}
				else
				{
					$current_sentence->pu_text($current_sentence->pu_text . "|\n");
				}

				if ( ($current_path->break == 1) ||
				     ($current_path->type eq "switch") )
				{
					print "never reach this sentence!!!!\n";
					$current_sentence->pu_text("#HotPink:You cannot reach this sentence!\n" . substr($current_sentence->pu_text, 1));
				}
			}

#			print "pu_text3 : " . $current_sentence->pu_text . "\n";
			if ($current_sentence->pu_text ne "")
			{
				&push_pu_text($current_sentence->pu_text);
			}
		}

		#/* 新しい実行PATH分岐 */
		if ($current_sentence->new_path ne "")
		{
			my $child_num;

			if ($current_sentence->pop_current_path == 1)
			{
				die "strange path relation!!\n";
			}

			$child_num = @{$current_path->child};
			&push_pu_text("Link to child[$child_num]\n");
			&new_path($current_function, $current_path, $global_data->indent);
			$current_path->type($current_sentence->new_path);
			$current_path->backward($current_sentence->backward);
			$current_path->switch_val($current_sentence->switch_val);
			
			if ($current_sentence->case_condition ne "")
			{
				my $push_text = $current_sentence->case_condition;
				&push_pu_text("$push_text\n");
			}
			
			if ($current_sentence->case_val ne "")
			{
#				printf "push case_val : %s to $current_path $current_path->case_val\n", $current_sentence->case_val;
				push @{$current_path->case_val}, $current_sentence->case_val;
			}
		}
		elsif ($current_sentence->pop_current_path == 1)
		{
			#/* 親の実行PATHに復帰する */
#			print "pop_current_path!!!! pu_text : " . $current_sentence->pu_text . "\n";
			&return_parent_path();
		}

		&clear_current_sentence();
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

	printf OUT_FILE_OUT "\nVariables List\n";
	printf OUT_FILE_OUT "\ttype\tname\tinit\tcomment\n";
	foreach $variable (@variables)
	{
		printf OUT_FILE_OUT "\t%s\t%s\t%s\t%s\n", $variable->typ,$variable->name,$variable->init,$variable->comment_txt;
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
		printf OUT_PU_OUT "\@enduml\n\n";
		close(OUT_PU_OUT);
		push @pu_files, $out_file;
	}
	
	if ($pu_convert == 1)
	{
		print "do pu convert!!! @pu_files\n";
		system("java -DPLANTUML_LIMIT_SIZE=8192 -jar plantuml.jar @pu_files")
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
	printf OUT_FUNC_TREE "\@endmindmap\n";

	if ($pu_convert == 1)
	{
		print "do pu convert!!! $out_file\n";
		system("java -DPLANTUML_LIMIT_SIZE=8192 -jar plantuml.jar $out_file")
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

	$pu_text =~ s/\n([^\n])/\n$indent_tab$1/g;
	push @{$current_path->pu_text}, $indent_tab . $pu_text;
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
		&push_pu_text("else (No)\nendif\n");
	}
	elsif ($path_type eq "else")
	{
		&push_pu_text("endif\n");
	}
	elsif ($path_type eq "while")
	{
		&push_pu_text("endwhile (No)\n}\n");
	}
	elsif ($path_type eq "for")
	{
		#/* for文の終わりには繰り返し前の処理とendwhileを挿入する */
		&push_pu_text("backward :$backward_text]\n");
		&push_pu_text("endwhile (No)\n");
		&push_pu_text("}\n");
	}
	elsif ($path_type eq "do")
	{
		$force_prev_word = "do";
	}
	elsif ($path_type eq "switch")
	{
		#/* ここに来るのはcaseもdefaultもないswitch文！ */
		print "switch sentence with no case or default!!!!\n";
		&push_pu_text("#HotPink:No case or default label!]\n}\n");
	}
	elsif ( ($path_type eq "case") ||
	        ($path_type eq "default") )
	{
		print "close bracket in case, default\n";
	}
	else
	{
		print "unhandled path close!!!!!!\n";
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
			printf OUT_PU_OUT "$text";
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

		if ($line_text =~ /^define[ \t]+([_A-Za-z][_A-Za-z0-9]*)[ \t]+([^\s]+)/)
		{
			print "define $1 as $2\n";
			add_valid_define($1, $2);
		}
		elsif ($line_text =~ /^define[ \t]+([_A-Za-z][_A-Za-z0-9]*)[ \t]*/)
		{
			print "define $1\n";
			add_valid_define($1, "");
		}
		elsif ($line_text =~ /^incpath[ \t]+([^\s]+)/)
		{
			print "include path $1\n";
			&add_array_no_duplicate(\@include_paths ,$1);
		}
		elsif ($line_text =~ /^include[ \t]+([^\s]+)/)
		{
			print "add target include file $1\n";
			&add_array_no_duplicate(\@target_include ,$1);
		}
	}
	close(SETTING_IN);
}
