import os
import sys
import re
import datetime
import subprocess


#/* グローバル変数 */
g_output_fld       = "m_analyze"
g_setting_file     = "m_analyze_setting.txt"
g_log_file_name    = ""
g_output_temp_text = 0
g_default_log      = 0
g_target_files     = []
g_module_name      = "sample"
g_jar_path         = ""
g_exec_c_analyze   = 1
g_charset_utf      = 0
g_modules          = []

class cVariable:
    name        = ""
    type        = ""
    summary     = ""
    is_static   = 0
    is_const    = 0
    is_extern   = 0
    func_read   = []
    func_write  = []

class cFunction:
    name        = ""
    summary     = ""
    ret_type    = ""
    lines       = 0
    steps       = 0
    paths       = 0
    is_static   = 0
    args        = []
    local_vals  = []
    func_call   = []
    func_called = []
    val_read    = []
    val_write   = []

class cModule:
    name         = ""
    lines        = 0
    steps        = 0
    paths        = 0
    includes     = []
    macros       = []
    typedefs     = []
    variables    = []
    functions    = []
    module_ref   = []
    module_refed = []

    def load_csv(self, file_path):
        global g_charset_utf

        if (g_charset_utf):
            csv = open(file_path, 'r', encoding="utf-8")
        else:
            csv = open(file_path, 'r')

        read_line = csv.readlines()
        csv.close();



#/*****************************************************************************/
#/* サブディレクトリの生成                                                    */
#/*****************************************************************************/
def make_directory(dirname):
    print("make dir! %s" % dirname)
    os.makedirs(os.path.join(dirname), exist_ok = True)



def search_dir(directory):
    global g_target_files

#   print ("search_dir %s" % directory)
    dirlist = []
    files = os.listdir(directory)
    for filename in files:
#       print("filename : %s" % filename)
        if (os.path.isdir(directory + "\\" + filename)):
            search_dir(directory + "\\" + filename)
        else:
            result = re.match(r".*\.[cChH]$", filename)
            if (result):
#               print ("Match! filename : %s" % filename)
                g_target_files.append(directory + "\\" + filename)

def check_command_line_option():
    global g_setting_file
    global g_output_fld
    global g_log_file_name
    global g_default_log
    global g_target_files
    global g_output_temp_text
    global g_exec_c_analyze
    global g_charset_utf

    argc = len(sys.argv)
    option = ""
    first  = 1

    if (argc == 1):
        print("analyze module by default setting.txt")

    for arg in sys.argv:
        if (first == 1):
            first = 0
            continue

#       print (arg)
        if (option == "s"):
            option = ""
            g_setting_file = arg
        elif (option == "o"):
            option = ""
            g_output_fld = arg
        elif (option == "l"):
            option = ""
            g_log_file_name = arg
        elif (arg == "-s"):
            option = "s"
        elif (arg == "-l"):
            option = "l"
        elif (arg == "-skip"):
            g_exec_c_analyze = 0
        elif (arg == "-utf"):
            g_charset_utf = 1
        elif (arg == "-o"):
            option = "o"
        elif (arg == "-t"):
            g_output_temp_text = 1
        elif (arg == "-dl"):
            print("default log file!")
            g_default_log = 1
        else:
            if (os.path.isdir(arg)):
#               print("directory! %s" % arg)
                search_dir(arg)
            elif (os.path.isfile(arg)):
#               print("file! %s" % arg)
                g_target_files.append(arg)
            else:
                print("unknown arg! %s" % arg)


#/*****************************************************************************/
#/* 設定ファイルの読み込み処理                                                */
#/*****************************************************************************/
def read_setting_file():
    global g_target_files
    global g_charset_utf

    print("read_setting_file");
    f = open(g_setting_file, 'r')
    lines = f.readlines()

    re_source  = re.compile(r"source\s+(.+)\n")
    re_jar     = re.compile(r"plantuml[ \t]+([^\s]+)")
    re_module  = re.compile(r"module_name[ \t]+([^\s]+)")
    re_charset = re.compile(r"default_charset[ \t]+([^\s]+)")

    for line in lines:
#       print ("line:%s" % line)
        if (result := re_source.match(line)):
            print ("source   : " + result.group(1))
            g_target_files.append(result.group(1))
        elif (result := re_jar.match(line)):
            print ("jar file : " + result.group(1))
            g_jar_path = result.group(1)
        elif (result := re_module.match(line)):
            print ("module   : " + result.group(1))
            g_module_name = result.group(1)
        elif (result := re_charset.match(line)):
            print ("charset  : " + result.group(1))
            if (result.group(1) == "UTF8"):
                g_charset_utf = 1
            else:
                g_charset_utf = 0

    f.close()


#/*****************************************************************************/
#/* ログファイル設定                                                          */
#/*****************************************************************************/
def log_settings():
    global g_log_file_name
    global g_output_fld

    log_path = ""

    print("log_settings")
    if (g_log_file_name != ""):
        log_path = g_output_fld + "\\" + g_log_file_name
    elif (g_default_log == 1):
        now = datetime.datetime.now()
        formatted_time = now.strftime("%Y%m%d_%H%M%S")
        log_path = g_output_fld + "\\m_analyze_log_" + formatted_time + ".log";

    print ("log_path : %s" % log_path)

    if (log_path != ""):
       log_file = open(log_path, "a")
       sys.stdout = log_file



#/*****************************************************************************/
#/* Cコード解析                                                               */
#/*****************************************************************************/
def c_analyze():
    global g_target_files
    global g_charset_utf

    print("c_analyze")
    for source_file in g_target_files:
        print("  analyzing %s" % source_file, file = sys.__stdout__)

        cmd_text = "perl c_analyze.pl -o %s %s" % (g_output_fld, source_file)

        if (g_output_temp_text == 1):
            cmd_text += " -t"

        if (g_charset_utf == 1):
            cmd_text += " -utf"

        subprocess.run(cmd_text, stdout=sys.stdout)

#/*****************************************************************************/
#/* モジュール解析                                                            */
#/*****************************************************************************/
def module_analyze():
    global g_target_files
    global g_modules

    print("module_analyze")
    for source_file in g_target_files:
        csv_file_name = os.path.basename(source_file) + "_analyzed.csv"
        print("read csv : %s" % csv_file_name, file = sys.__stdout__);
        csv_file_name = g_output_fld + "\\" + csv_file_name
        module = cModule()
        module.load_csv(csv_file_name)
        g_modules.append(module)



#/*****************************************************************************/
#/* メイン関数                                                                */
#/*****************************************************************************/
def main():
    check_command_line_option()
    make_directory(g_output_fld)
    read_setting_file()
    log_settings()

    if (g_exec_c_analyze):
        c_analyze()

    module_analyze()




if __name__ == "__main__":
    main()


