import os
import sys
import re
import datetime
import subprocess
import difflib
from pathlib import Path


g_former_files = []
g_latter_files = []
g_output_fld   = "03_merged"

re_pu_line1    = re.compile(r"^(\s+\:)(.+)([\|\]])\n$")
re_pu_line2    = re.compile(r"^(\s+\:)(.+)\n$")
re_pu_line3    = re.compile(r"^( +)(.+)([\|\]])\n$")
re_pu_line4    = re.compile(r"^( +)(.+)\n$")


#/*****************************************************************************/
#/* サブディレクトリの生成                                                    */
#/*****************************************************************************/
def make_directory(dirname):
    print("make dir! %s" % dirname)
    os.makedirs(os.path.join(dirname), exist_ok = True)

#/*****************************************************************************/
#/* 引数確認                                                                  */
#/*****************************************************************************/
def check_command_line_option():
    global g_former_files
    global g_latter_files
    global g_output_fld

    argc = len(sys.argv)
    option = ""

    if (argc < 3):
        print("func_flow_merge.py : former latter")
        return

    sys.argv.pop(0)

    former_path = sys.argv.pop(0)
    if (os.path.isdir(former_path)):
        search_dir(0, former_path)
    elif (os.path.isfile(former_path)):
        g_former_files.append(former_path)

    latter_path = sys.argv.pop(0)
    if (os.path.isdir(latter_path)):
        search_dir(1, latter_path)
    elif (os.path.isfile(latter_path)):
        g_former_files.append(latter_path)

    if (argc > 3):
        out_path = sys.argv.pop(0)
        if (out_path != None):
            g_output_fld = out_path



#/*****************************************************************************/
#/* puファイル検索                                                            */
#/*****************************************************************************/
def search_dir(is_latter, directory):
    global g_former_files
    global g_latter_files

    print ("search_dir %s" % directory)
    files = os.listdir(directory)
    for filename in files:
        if (os.path.isdir(directory + "\\" + filename)):
            search_dir(is_latter, directory + "\\" + filename)
        else:
            result = re.match(r".+\.pu$", filename)
            if (result):
                print ("Match! filename : %s" % filename)
                if (is_latter):
                    g_latter_files.append(directory + "\\" + filename)
                else:
                    g_former_files.append(directory + "\\" + filename)


def replace_line(array_to_append, line):
    if (result := re_pu_line1.match(line)):
#       print("match1:%s" % line)
#       print("  %s" % result.group(1))
#       print("  %s" % result.group(2))
#       print("  %s" % result.group(3))
        array_to_append.append(result.group(1) + "\n")
        array_to_append.append(result.group(2) + "\n")
        array_to_append.append(result.group(3) + "\n")
    elif (result := re_pu_line2.match(line)):
#       print("match2:%s" % line)
#       print("  %s" % result.group(1))
#       print("  %s" % result.group(2))
        array_to_append.append(result.group(1) + "\n")
        array_to_append.append(result.group(2) + "\n")
    elif (result := re_pu_line3.match(line)):
#       print("match3:%s" % line)
#       print("  %s" % result.group(1))
#       print("  %s" % result.group(2))
#       print("  %s" % result.group(3))
        array_to_append.append(result.group(1) + "\n")
        array_to_append.append(result.group(2) + "\n")
        array_to_append.append(result.group(3) + "\n")
    elif (result := re_pu_line4.match(line)):
#       print("match4:%s" % line)
#       print("  %s" % result.group(1))
#       print("  %s" % result.group(2))
        array_to_append.append(result.group(1) + "\n")
        array_to_append.append(result.group(2) + "\n")
    else:
#       print("match0:%s" % line)
        array_to_append.append(line)


def read_diffs(former_path, latter_path):
    print("read_diffs for %s" % os.path.basename(latter_path))
    diff = difflib.Differ()
    f_former = open(former_path, 'r', encoding="utf-8")
    f_latter = open(latter_path, 'r', encoding="utf-8")

    former_lines = f_former.readlines()
    latter_lines = f_latter.readlines()

    former_input = []
    latter_input = []

    out_former = open(g_output_fld + "\\" + "former.pu", "w")
    for line in former_lines:
        replace_line(former_input, line)

    for line in former_input:
        print(line, file = out_former)

    out_former.close()

    out_latter = open(g_output_fld + "\\" + "latter.pu", "w")
    for line in latter_lines:
        replace_line(latter_input, line)

    for line in latter_input:
        print(line, file = out_latter)

    out_latter.close()

    output_diff = diff.compare(former_input, latter_input)
#   output_diff = diff.compare(former_lines, latter_lines)
#   print('\n'.join(output_diff))
    for line in output_diff:
        print(line, end="")

    f_former.close()
    f_latter.close()


def merge_pu_files():
    global g_former_files
    global g_latter_files

    print("merge_pu_files")
    for latter_path in g_latter_files:
        for former_path in g_former_files:
            if (os.path.basename(latter_path) == os.path.basename(former_path)):
                read_diffs(former_path, latter_path)


#/*****************************************************************************/
#/* ログファイル設定                                                          */
#/*****************************************************************************/
def log_settings():
    global g_output_fld

    now = datetime.datetime.now()
    formatted_time = now.strftime("%Y%m%d_%H%M%S")
    log_path = g_output_fld + "\\func_flow_log_" + formatted_time + ".log";

    print ("log_path : %s" % log_path)

    if (log_path != ""):
        log_file = open(log_path, "a")
        sys.stdout = log_file


#/*****************************************************************************/
#/* メイン関数                                                                */
#/*****************************************************************************/
def main():
    check_command_line_option()
    make_directory(g_output_fld)
    log_settings()
    merge_pu_files()


if __name__ == "__main__":
    main()





