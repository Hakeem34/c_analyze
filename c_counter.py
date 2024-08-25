import os
import sys
import re
import subprocess
import errno
import time
import datetime
import chardet
import unicodedata

from pathlib  import Path


g_include_paths   = []
g_macro_defs      = []
g_target_files    = []


#/* コマンドライン引数に関する正規表現 */
re_arg_macro_val  = re.compile(r"^\-D([^=]+)\=(.*)$")
re_arg_macro_only = re.compile(r"^\-D([^=]+)$")
re_arg_macro_args = re.compile(r"^([^\(]+)\(([^\)]+)\)$")
re_arg_inc_path   = re.compile(r"^\-I(.+)$")


#/* ディレクティブに関する正規表現 */
re_directive_include = re.compile(r"^\s*#\s*include\s*(.+)$")
re_directive_define  = re.compile(r"^\s*#\s*define\s*(.+)$")


class cMacroDefine:
    def __init__(self):
        self.name        = ""
        self.value       = ""
        self.is_function = 0
        self.ext_option  = 0
        self.args        = []
        return


#/*****************************************************************************/
#/* 重複無しのappend処理                                                      */
#/*****************************************************************************/
def append_wo_duplicate(list, item):
    if (item in list):
        return

    list.append(item)
    return


#/*****************************************************************************/
#/* 設定ファイル読み込み処理                                                  */
#/*****************************************************************************/
def add_macro_def(name, value):
    global g_macro_defs

#    print("macro define %s : %s" % (name, value))
    macro_def = cMacroDefine()

    if (result := re_arg_macro_args.match(name)):
        macro_def.name        = result.group(1)
        macro_def.args        = result.group(2).split('\n')
        macro_def.is_function = 1
#        print("macro function! name : %s, args : %s" % (result.group(1),  result.group(2)))
    else:
        macro_def.name        = name
        macro_def.is_function = 0

    macro_def.value = value

    g_macro_defs.append(macro_def)
    return macro_def


#/*****************************************************************************/
#/* 設定ファイル読み込み処理                                                  */
#/*****************************************************************************/
def read_setting_file(file_path):
    return


#/*****************************************************************************/
#/* コマンドライン引数処理                                                    */
#/*****************************************************************************/
def check_command_line_option():
    global g_include_paths
    global g_target_files

    option = ""
    sys.argv.pop(0)
    for arg in sys.argv:
#       print("arg : %s" % arg)
        if (result := re_arg_macro_val.match(arg)):
            macro_def = add_macro_def(result.group(1), result.group(2))
        elif (result := re_arg_macro_only.match(arg)):
            macro_def = add_macro_def(result.group(1), "")
        elif (result := re_arg_inc_path.match(arg)):
            inc_path = result.group(1)
#           print("-I [%s]" % (inc_path))
            append_wo_duplicate(g_include_paths, inc_path)
        elif (os.path.isfile(arg)):
#           print("Target File! : %s" % (arg))
            g_target_files.append(arg)
        else:
            print("Ignore Arg : %s" % (arg))

    return


#/*****************************************************************************/
#/* 処理開始ログ                                                              */
#/*****************************************************************************/
def log_start():
    now = datetime.datetime.now()

    time_stamp = now.strftime('%Y%m%d_%H%M%S')
    log_path = 'c_count_' + time_stamp + '.txt'
    log_file = open(log_path, "w")
    sys.stdout = log_file

    start_time = time.perf_counter()
    now = datetime.datetime.now()
    print("処理開始 : " + str(now))
    print ("----------------------------------------------------------------------------------------------------------------")
    return start_time


#/*****************************************************************************/
#/* 処理終了ログ                                                              */
#/*****************************************************************************/
def log_end(start_time):
    end_time = time.perf_counter()
    now = datetime.datetime.now()
    print ("----------------------------------------------------------------------------------------------------------------")
    print("処理終了 : " + str(now))
    second = int(end_time - start_time)
    msec   = ((end_time - start_time) - second) * 1000
    minute = second / 60
    second = second % 60
    print("  %dmin %dsec %dmsec" % (minute, second, msec))
    return


#/*****************************************************************************/
#/* コマンドラインオプションの表示                                            */
#/*****************************************************************************/
def log_comand_line_options():
    global g_include_paths
    global g_macro_defs
    global g_target_files

    print ("----------------------------------------------------------------------------------------------------------------")
    print ("コマンドラインオプション(対象ファイル)")
    count = 0
    for target_file in g_target_files:
        print("  [%d]%s" % (count, target_file))
        count += 1

    print ("コマンドラインオプション(インクルードパス)")
    count = 0
    for inc_path in g_include_paths:
        print("  [%d]%s" % (count, inc_path))
        count += 1

    print ("コマンドラインオプション(マクロ定義)")
    count = 0
    for macro_def in g_macro_defs:
        if (macro_def.is_function):
            print("  [%d]%s(%s) : %s" % (count, macro_def.name, (',').join(macro_def.args), macro_def.value))
        else:
            print("  [%d]%s : %s" % (count, macro_def.name, macro_def.value))
        count += 1

    return


#/*****************************************************************************/
#/* 入力ファイルのカウント処理                                                */
#/*****************************************************************************/
def count_input_file(target_file):
    print ("----------------------------------------------------------------------------------------------------------------")
    print ("対象：%s" % (target_file))
    f = open(target_file, 'r')
    lines = f.readlines()

    line_count = 1
    for line_text in lines:
#       print(line_text)
        if (result := re_directive_include.match(line_text)):
            print("  [%d]include : %s" % (line_count, result.group(1)))
        elif (result := re_directive_define.match(line_text)):
            print("  [%d]define : %s" % (line_count, result.group(1)))

        line_count += 1


    f.close()
    return


#/*****************************************************************************/
#/* ファイルリストのカウント処理                                              */
#/*****************************************************************************/
def count_input_files():
    global g_target_files

    print ("----------------------------------------------------------------------------------------------------------------")
    print ("カウント処理開始")
    for target in g_target_files:
        count_input_file(target)

    return


#/*****************************************************************************/
#/* メイン関数                                                                */
#/*****************************************************************************/
def main():
    check_command_line_option()
    start_time = log_start()

    log_comand_line_options()
    count_input_files()

    log_end(start_time)
    return


if __name__ == "__main__":
    main()
