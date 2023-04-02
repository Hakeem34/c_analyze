import os
import sys
import re
import datetime
import subprocess


#/* 正規表現 */
re_total_lines     = re.compile(r"^Total Lines\s+(\d+)\n")
re_total_steps     = re.compile(r"^Total Steps\s+(\d+)\n")
re_total_comments  = re.compile(r"^Total Comment\s+(\d+)\n")
re_inc_files       = re.compile(r"^Include Files\n")
re_macro_defs      = re.compile(r"^macro defs\n")
re_type_defs       = re.compile(r"^type defs\n")
re_variables       = re.compile(r"^Variables List\n")
re_functions       = re.compile(r"^Function List\n")
re_function_detail = re.compile(r"^Function Detail\n")

re_include_file     = re.compile(r"^\t([^\t]+)\n$")
re_variables_line   = re.compile(r"^\t([^\t]+)\t([^\t]+)\t([^\t]+)\t([^\t]+)\t([^\t]+)\t([^\t]+)\n$")
re_functions_line   = re.compile(r"^\t([^\t]+)\t([^\t]+)\t([^\t]+)\t([^\t]+)\t([^\t]+)\t([^\t]+)\t([^\t]+)\t([^\t]+)\n$")
re_detail_name      = re.compile(r"^\tName  \t([^\n]+)\n$")
re_detail_local     = re.compile(r"^\tLocal Variable\n$")
re_detail_func2call = re.compile(r"^\tFunctions call to\n$")
re_detail_called    = re.compile(r"^\tcalled from\n$")
re_detail_var_wr    = re.compile(r"^\tVariables write to\n$")
re_detail_var_rd    = re.compile(r"^\tVariables read from\n$")
re_detail_array      = re.compile(r"^\t\[(\d+)\]\t([^\n]+)\n$")


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
    init_val    = ""
    is_static   = 0
    is_const    = 0
    is_extern   = 0
    func_read   = []
    func_write  = []

class cFunction:
    name        = ""
    ret_type    = ""
    summary     = ""
    is_static   = 0
    lines       = 0
    steps       = 0
    comments    = 0
    paths       = 0
    args        = []
    local_vars  = []
    func_call   = []
    func_called = []
    var_read    = []
    var_write   = []

class cModule:
    name         = ""
    lines        = 0
    steps        = 0
    comments     = 0
    paths        = 0
    current_mode = ""
    includes     = []
    macros       = []
    typedefs     = []
    variables    = []
    functions    = []
    module_ref   = []
    module_refed = []

    #/* 内部処理用変数 */
    skip_line    = 0
    detail_phase = 0
    current_func = 0

    def get_function(self, name):
        for function in self.functions:
            if (function.name == name):
                return function

        return

    def check_top_level(self, line):
#       print ("chack_top_level")
        if (result := re_total_lines.match(line)):
            print ("Total Lines  : " + result.group(1))
            self.lines = result.group(1)
        elif (result := re_total_steps.match(line)):
            print ("Total Steps  : " + result.group(1))
            self.steps = result.group(1)
        elif (result := re_total_comments.match(line)):
            print ("Total Comments  : " + result.group(1))
            self.comments = result.group(1)
        elif (result := re_inc_files.match(line)):
            return "include"
        elif (result := re_macro_defs.match(line)):
            self.skip_line = 1
            return "macro"
        elif (result := re_type_defs.match(line)):
            self.skip_line = 1
            return "type"
        elif (result := re_variables.match(line)):
            self.skip_line = 1
            return "variable"
        elif (result := re_functions.match(line)):
            self.skip_line = 1
            return "function"
        elif (result := re_function_detail.match(line)):
            return "detail"

        return "none"

    def parse_include_line(self, line):
#       print("include line : %s" % line)
        if (result := re_include_file.match(line)):
            print("include : %s" % result.group(1))
            self.includes.append(result.group(1))
        return

    def parse_macro_line(self, line):
        return

    def parse_type_line(self, line):
        return

    #/*****************************************************************************/
    #/* 変数概要の読み込み                                                        */
    #/*****************************************************************************/
    def parse_variable_line(self, line):
        if (result := re_variables_line.match(line)):
            print("variable : %s" % result.group(2))
            aVariable = cVariable()
            aVariable.type      = result.group(1)
            aVariable.name      = result.group(2)
            aVariable.init_val  = result.group(3)
            aVariable.summary   = result.group(4)
            aVariable.is_static = result.group(5)
            aVariable.is_extern = result.group(6)
            return aVariable
        return None

    #/*****************************************************************************/
    #/* 関数概要の読み込み                                                        */
    #/*****************************************************************************/
    def parse_function_line(self, line):
        if (result := re_functions_line.match(line)):
            print("function : %s" % result.group(1))
            aFunction = cFunction()
            aFunction.name      = result.group(1)
            aFunction.ret_type  = result.group(2)
            aFunction.summary   = result.group(3)
            aFunction.is_static = result.group(4)
            aFunction.lines = result.group(5)
            aFunction.steps = result.group(6)
            aFunction.comments = result.group(7)
            aFunction.paths = result.group(8)
            return aFunction
        return None

    #/*****************************************************************************/
    #/* 関数詳細の読み込み                                                        */
    #/*****************************************************************************/
    def parse_detail_line(self, line):
        if (self.detail_phase == 0):
            #/* まず関数名を拾い、ローカル変数定義の先頭を見つける */
            if (result := re_detail_name.match(line)):
                print("detail : %s" % result.group(1))
                self.current_func = self.get_function(result.group(1))
            elif (result := re_detail_local.match(line)):
                self.detail_phase = 1
                self.skip_line = 1
        elif (self.detail_phase == 1):
            #/* 次に呼び出す関数の先頭を見つける */
            if (result := re_detail_func2call.match(line)):
                self.detail_phase = 2
            else:
                ret_val = self.parse_variable_line(line)
                if (ret_val != None):
                    self.current_func.local_vars.append(ret_val)
        elif (self.detail_phase == 2):
            #/* 次に呼び出されている関数の先頭を見つける */
            if (result := re_detail_called.match(line)):
                self.detail_phase = 3
            elif (result := re_detail_array.match(line)):
                self.current_func.func_call.append(result.group(2))
        elif (self.detail_phase == 3):
            #/* 次に書き込む変数の先頭を見つける */
            if (result := re_detail_var_wr.match(line)):
                self.detail_phase = 4
            elif (result := re_detail_array.match(line)):
                self.current_func.func_called.append(result.group(2))
        elif (self.detail_phase == 4):
            #/* 次に読み出す変数の先頭を見つける */
            if (result := re_detail_var_rd.match(line)):
                self.detail_phase = 5
            elif (result := re_detail_array.match(line)):
                self.current_func.var_read.append(result.group(2))
        elif (self.detail_phase == 5):
            #/* 最後、読み出す変数がヒットしなくなったら、次の関数を探す */
            if (result := re_detail_array.match(line)):
                self.current_func.var_write.append(result.group(2))
            else:
                self.detail_phase = 0
        return


    #/*****************************************************************************/
    #/* コード解析結果の読み込み                                                  */
    #/*****************************************************************************/
    def load_csv(self, file_path):
        global g_charset_utf

        if (g_charset_utf):
            csv = open(file_path, 'r', encoding="utf-8")
        else:
            csv = open(file_path, 'r')

        read_lines = csv.readlines()
        self.skip_line = 0
        for line in read_lines:
            ret_text = self.check_top_level(line)
            if (ret_text != "none"):
                print("ret_text : %s" % ret_text)
                self.current_mode = ret_text
                continue
            else:
                if (self.skip_line == 1):
                    self.skip_line = 0
                    continue

            if (self.current_mode == "include"):
                self.parse_include_line(line)
            elif (self.current_mode == "macro"):
                self.parse_macro_line(line)
            elif (self.current_mode == "type"):
                self.parse_type_line(line)
            elif (self.current_mode == "variable"):
                ret_val = self.parse_variable_line(line)
                if (ret_val != None):
#                   print("add variable!")
                    self.variables.append(ret_val)
            elif (self.current_mode == "function"):
                ret_val = self.parse_function_line(line)
                if (ret_val != None):
#                   print("add function!")
                    self.functions.append(ret_val)
            elif (self.current_mode == "detail"):
                self.parse_detail_line(line)


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


