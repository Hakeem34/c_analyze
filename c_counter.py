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


g_cwd             = os.getcwd()
g_include_paths   = []
g_macro_defs      = []
g_target_file     = ''
g_file_infos      = []



#/* ディレクティブ */
C_DIRECTIVES = ['if', 'else', 'elif', 'endif', 'ifdef', 'ifndef', 'define', 'undef', 'include', 'error', 'pragma', 'line']

#/* 予約語 */
C_KEYWORDS = ['auto', 'break', 'case', 'char', 'const', 'continue', 'default', 'do', 'double', 'else', 'enum', 'extern', 
              'float', 'for', 'goto', 'if', 'inline', 'int', 'long', 'register', 'restrict', 'return', 'short', 'signed', 'sizeof',
              'static', 'struct', 'switch', 'typedef', 'union', 'unsigned', 'void', 'volatile', 'while']


#/* 2文字以上の区切り文字（コメントクローズはここでは処理しない） */
C_PUNCTUATOR = ['/*', '//', '+=', '-=', '*=', '/=', '%=', '++', '--', '<<', '>>', '<<=', '>>=', '->', 
                '==', '!=', '<=', '>=', '&&', '||', '&=', ' ^=', ' |=', '##']


#/* コマンドライン引数に関する正規表現 */
RE_ARG_MACRO_VAL  = re.compile(r'^\-D([^=]+)\=(.*)$')
RE_ARG_MACRO_ONLY = re.compile(r'^\-D([^=]+)$')
RE_ARG_MACRO_ARGS = re.compile(r'^([^\(]+)\(([^\)]+)\)$')
RE_ARG_INC_PATH   = re.compile(r'^\-I(.+)$')


RE_SPACE_ONLY        = re.compile(r'^\s*$')
RE_C_IDENTIFIER_1ST  = re.compile(r'[_a-zA-Z]')

RE_C_COMMENT_CLOSE   = re.compile(r'^(.*?)\*\/')
RE_DQ_LIT_CLOSE      = re.compile(r'^([^\\|\"]*)([\\|\"])(.*)')
RE_SYS_INCLUDE_CLOSE = re.compile(r'^([^\\|\>]*)([\\|\>])(.*)')
RE_SQ_LIT_CLOSE      = re.compile(r'^([^\\|\']*)([\\|\'])(.*)')
RE_COMMENT_SPLICING  = re.compile(r'^(.*)\\\s*$')






re_line_integrate    = re.compile(r"(.*)\\\s*$")

HARD_TAB_LENGTH    = 4

NEW_LINE_CODE_LF   = 0
NEW_LINE_CODE_CR   = 1
NEW_LINE_CODE_CRLF = 2
NEW_LINE_CODE_MIX  = 3
NEW_LINE_CODE_NONE = 4


TOKEN_KEYWORD       = 0          #/* 予約語                           */
TOKEN_IDENTIFIER    = 1          #/* 識別子                           */
TOKEN_CONSTANT      = 2          #/* 定数（文字列、文字定数除く）     */
TOKEN_PUNCTUATOR    = 3          #/* 区切り文字（スペース除く）       */
TOKEN_COMMENT_C     = 4          #/* C言語コメント                    */
TOKEN_COMMENT_CPP   = 5          #/* C++コメント                      */
TOKEN_DQ_LITERAL    = 6          #/* ダブルクォーテーションリテラル   */
TOKEN_SQ_LITERAL    = 7          #/* シングルクォーテーションリテラル */
TOKEN_LF            = 9          #/* 区切り文字（改行）               */
TOKEN_OTHER         = 10         #/* その他                           */

C_STATE_NONE        = 0
C_STATE_C_COMMENT   = 1
C_STATE_CPP_COMMENT = 2
C_STATE_DQ_LITERAL  = 3
C_STATE_SQ_LITERAL  = 4


SENTENCE_NONE       = 0
SENTENCE_FORMULA    = 1          #/* 式                               */
SENTENCE_CONTROL    = 2          #/* 制御文                           */
SENTENCE_DECLARE    = 3          #/* 宣言                             */
SENTENCE_DIRECTIVE  = 4          #/* ディレクティブ                   */




LINE_END_OFFSET     = -1


class cColumnRow:
    __slots__ = ('column', 'row')
    def __init__(self, row, column):
        self.row    = row
        self.column = column
        return


class cToken:
    __slots__ = ('type', 'start', 'end', 'text')
    def __init__(self, type, start):
        self.type  = type
        self.start = start
        self.end   = None
        self.text  = ''
        return


class cTokenizer:
    __slots__ = ('tokens', 'comments', 'current_token', 'splicing_line', 'parent', 'current_state', 'directive')
    def __init__(self, parent):
        self.comments = []
        self.tokens   = []
        self.current_state   = C_STATE_NONE
        self.current_token   = None
        self.splicing_line   = ''
        self.directive       = ''
        self.parent          = parent
        return


    #/*****************************************************************************/
    #/* 1文字トークンの追加                                                       */
    #/*****************************************************************************/
    def add_single_char_token(self, line_num, start, type, character):
        token = cToken(type , cColumnRow(line_num, start))
        token.text = character
        token.end  = cColumnRow(line_num, start + 1)
        return token


    #/*****************************************************************************/
    #/* 現在のトークンを閉じる                                                    */
    #/*****************************************************************************/
    def close_current_token(self, line_num, offset):
        if (self.current_token):
            if (self.current_token.type == TOKEN_IDENTIFIER):
                if (self.current_token.text in C_KEYWORDS):
                    self.current_token.type = TOKEN_KEYWORD
#                   print_log(f'  KEYWORD : {self.current_token.text}')
                    pass
                else:
#                   print_log(f'  SYMBOL  : {self.current_token.text}')
                    pass
            elif (self.current_token.type == TOKEN_PUNCTUATOR):
#               print_log(f'  PUNCTUATOR  : {self.current_token.text}')
                pass
            elif (self.current_token.type == TOKEN_CONSTANT):
#               print_log(f'  CONSTANT    : {self.current_token.text}')
                pass
            elif (self.current_token.type == TOKEN_OTHER):
                pass
            else:
                pass

            self.current_token.end = cColumnRow(line_num, offset)
            self.tokens.append(self.current_token)
            self.current_token = None
        return

    #/*****************************************************************************/
    #/* トークン処理(通常)                                                        */
    #/*****************************************************************************/
    def tokenize_line_normal(self, line_num, offset, text):
        ret_offset    = offset
        offset_text   = text[offset:]
        line_splicing = False

        if (offset == 0):
            print_log(f'[{line_num}] : {text[:-1]}')

        for character in offset_text:
#           print_log(f'{character}')
            close_token = False
            new_token   = None         #/* 完結しており即座に追加するトークン    */
            next_token  = None         #/* 未完結で次のcurrentとなるトークン     */

            if (line_splicing):
                if (character != '\n') and (character != ' ') and (re.match(r'^#include', self.directive) == None):
                    print_log(f'something wrong!  line splicing! \\ : {text} / {self.directive}')
                    exit(-1)
            elif (character == '\n'):
                close_token = True
                new_token = self.add_single_char_token(line_num, ret_offset, TOKEN_LF, character)
#               print_log(f'  LF and clear directive! : {self.directive}')
                self.directive = ''
            elif (character == ' '):
                close_token = True
            elif (character == '\\'):
                line_splicing = True
            elif (character == '"') or (character == "'") or ((self.directive == '#include') and (character == '<')):
                #/* シングルorダブルクォーテーションで文字、文字列定数が開始する場合は、現状のtokenを閉じて、この関数での処理を終える */
                self.close_current_token(line_num, ret_offset + 1)

                if (character == '"') or (character == '<'):
                    self.current_token = cToken(TOKEN_DQ_LITERAL, cColumnRow(line_num, ret_offset))
                    self.current_state = C_STATE_DQ_LITERAL
                elif (character == "'"):
                    self.current_token = cToken(TOKEN_SQ_LITERAL, cColumnRow(line_num, ret_offset))
                    self.current_state = C_STATE_SQ_LITERAL

                self.current_token.text = character
                return ret_offset + 1
            elif (character.isdigit()):
                #/* 数値 [0-9] */
                if (self.current_token):
                    if (self.current_token.type == TOKEN_IDENTIFIER):
                        self.current_token.text += character
                    elif (self.current_token.type == TOKEN_CONSTANT):
                        self.current_token.text += character
                    elif (self.current_token.type == TOKEN_OTHER) and (self.current_token.text == '.'):
                        self.current_token.type  = TOKEN_CONSTANT
                        self.current_token.text += character
                    else:
                        close_token = True
                        next_token = cToken(TOKEN_CONSTANT, cColumnRow(line_num, ret_offset))
                        next_token.text = character
                else:
                    next_token = cToken(TOKEN_CONSTANT, cColumnRow(line_num, ret_offset))
                    next_token.text = character
            elif (result := RE_C_IDENTIFIER_1ST.match(character)):
                #/* ASCII文字 [_a-zA-Z] */
                if (self.directive != ''):
                    self.directive += character

                if (self.current_token):
                    if (self.current_token.type == TOKEN_IDENTIFIER):
                        self.current_token.text += character
                    elif (self.current_token.type == TOKEN_CONSTANT):
                        self.current_token.text += character
                    else:
                        close_token = True
                        next_token = cToken(TOKEN_IDENTIFIER, cColumnRow(line_num, ret_offset))
                        next_token.text = character
                else:
                    next_token = cToken(TOKEN_IDENTIFIER, cColumnRow(line_num, ret_offset))
                    next_token.text = character
            elif (character == '.'):
                #/* .は特殊な扱い。トークンの先頭に.が来た場合は、浮動小数定数の場合と区切り文字の場合の二パターンがある */
                if (self.current_token):
                    if (self.current_token.type == TOKEN_IDENTIFIER):
                        close_token = True
                        next_token = cToken(TOKEN_PUNCTUATOR, cColumnRow(line_num, ret_offset))
                        next_token.text = character
                    elif (self.current_token.type == TOKEN_CONSTANT):
                        self.current_token.text += character
                    elif (self.current_token.type == TOKEN_PUNCTUATOR):
                        if (self.current_token.text == '.') or (self.current_token.text == '..'):
                            #/* ...でマクロの可変長引数  */
                            self.current_token.text += character
                        else:
                            close_token = True
                            next_token = cToken(TOKEN_OTHER, cColumnRow(line_num, ret_offset))
                            next_token.text = character

                else:
                    next_token = cToken(TOKEN_OTHER, cColumnRow(line_num, ret_offset))
                    next_token.text = character
            else:
                #/* その他の区切り文字(PUNCTUATOR) */
                if (self.current_token):
                    if (self.current_token.type == TOKEN_PUNCTUATOR) and (self.current_token.text + character) in C_PUNCTUATOR:
                        self.current_token.text += character

                        #/* コメント区間は処理を切り替える */
                        if (self.current_token.text == '//'):
                            self.current_token.type = TOKEN_COMMENT_CPP
                            self.current_token.text = '//'
                            self.current_state = C_STATE_CPP_COMMENT
                            return ret_offset + 1
                        elif (self.current_token.text == '/*'):
                            self.current_token.type = TOKEN_COMMENT_C
                            self.current_token.text = '/*'
                            self.current_state = C_STATE_C_COMMENT
                            return ret_offset + 1
                    elif (self.current_token.type == TOKEN_CONSTANT) and ((character == '+') or (character == '-')) and (self.current_token.text[-1] in ['e','E','p','P']):
                        #/* 定数定義でe、pの直後に来る+, -は浮動小数の指数部のため、区切り文字ではない */
                        self.current_token.text += character
                    else:
                        close_token = True
                        next_token = cToken(TOKEN_PUNCTUATOR, cColumnRow(line_num, ret_offset))
                        next_token.text = character
                else:
                    next_token = cToken(TOKEN_PUNCTUATOR, cColumnRow(line_num, ret_offset))
                    next_token.text = character
                    if (character == '#'):
                        self.directive = '#'

            if (close_token):
                self.close_current_token(line_num, ret_offset + 1)

            if (new_token):
                self.tokens.append(new_token)

            if (next_token):
                self.current_token = next_token

            ret_offset += 1

        return LINE_END_OFFSET


    #/*****************************************************************************/
    #/* トークン処理(Cコメント)                                                   */
    #/*****************************************************************************/
    def tokenize_line_c_comment(self, line_num, offset, text):
        ret_offset = LINE_END_OFFSET
        offset_text = text[offset:]

        if (result := RE_C_COMMENT_CLOSE.match(offset_text)):
            comment     = result.group(1)
            length      = len(comment)
            ret_offset  = offset + length + 2
            self.current_token.text += (comment + '*/')
            self.current_token.end   = cColumnRow(line_num, ret_offset)
#           print_log(f'  C COMMENT {self.current_token.text}')

            self.tokens.append(self.current_token)
            self.current_token = None
            self.current_state = C_STATE_NONE
        else:
            self.current_token.text += (offset_text)

        return ret_offset


    #/*****************************************************************************/
    #/* トークン処理(C++コメント)                                                 */
    #/*****************************************************************************/
    def tokenize_line_cpp_comment(self, line_num, offset, text):
        ret_offset = LINE_END_OFFSET
        offset_text = text[offset:]

#       print_log(f'  tokenize_line_cpp_comment({offset_text})')
        if (result := RE_COMMENT_SPLICING.match(offset_text)):
            comment     = result.group(1)
            length      = len(comment)
            self.current_token.text += (comment + '\n')
#           print_log(f'  CPP COMMENT SPLICING!')
        else:
            self.current_token.text += offset_text[:-1]
            self.current_token.end   = cColumnRow(line_num, len(text))
#           print_log(f'  CPP COMMENT {self.current_token.text}')

            self.tokens.append(self.current_token)
            self.current_token = None
            self.current_state = C_STATE_NONE
            new_token = self.add_single_char_token(line_num, ret_offset, TOKEN_LF, '\n')
            self.tokens.append(new_token)

        return ret_offset


    #/*****************************************************************************/
    #/* トークン処理(文字列リテラル)                                              */
    #/*****************************************************************************/
    def tokenize_line_dq_literal(self, line_num, offset, text):
        ret_offset = LINE_END_OFFSET
        offset_text = text[offset:]

        first = self.current_token.text[0]
        if (first == '"'):
            result = RE_DQ_LIT_CLOSE.match(offset_text)
            second = first
        elif (first == '<'):
            result = RE_SYS_INCLUDE_CLOSE.match(offset_text)
            second = '>'

        if (result):
            literal = result.group(1)
            judge   = result.group(2)
            remain  = result.group(3)
            length  = len(literal)
            if (judge == second):
                #/* ダブルクォーテーションで閉じられている場合 */
                ret_offset  = offset + length + 1
                self.current_token.text += (literal + second)
                self.current_token.end   = cColumnRow(line_num, ret_offset)
#               print_log(f'  DQ LIT : {self.current_token.text}')
                self.tokens.append(self.current_token)
                self.current_token = None
                self.current_state = C_STATE_NONE
            elif (judge == '\\'):
                #/* エスケープ文字(¥)が現れた場合 */
                if (result := RE_SPACE_ONLY.match(remain)):
#                   print_log(f'  splicing in ""')
                    self.current_token.text += literal
                else:
#                   print_log(f'  escape in "" \\{remain[0]}')
                    ret_offset  = offset + length + 2
                    self.current_token.text += (literal + '\\' + remain[0])
        else:
            print_log(f'something wrong!  dq literal : {offset_text}')
            exit(-1)


        return ret_offset


    #/*****************************************************************************/
    #/* トークン処理(文字定数リテラル)                                            */
    #/*****************************************************************************/
    def tokenize_line_sq_literal(self, line_num, offset, text):
        ret_offset = LINE_END_OFFSET
        offset_text = text[offset:]

        if (result := RE_SQ_LIT_CLOSE.match(offset_text)):
            literal = result.group(1)
            judge   = result.group(2)
            remain  = result.group(3)
            length  = len(literal)
            if (judge == "'"):
                #/* シングルクォーテーションで閉じられている場合 */
                ret_offset  = offset + length + 1
                self.current_token.text += (literal + "'")
                self.current_token.end   = cColumnRow(line_num, ret_offset)
#               print_log(f'  DQ LIT : {self.current_token.text}')
                self.tokens.append(self.current_token)
                self.current_token = None
                self.current_state = C_STATE_NONE
            else:
                #/* エスケープ文字(¥)が現れた場合 */
                if (result := RE_SPACE_ONLY.match(remain)):
#                   print_log(f'  splicing in \'\'')
                    self.current_token.text += literal
                else:
#                   print_log(f'  escape in \'\' \\{remain[0]}')
                    ret_offset  = offset + length + 2
                    self.current_token.text += (literal + '\\' + remain[0])
        else:
            print_log(f'something wrong!  sq literal : {offset_text}')
            exit(-1)

        return ret_offset


    #/*****************************************************************************/
    #/* トークンへの分割                                                          */
    #/*****************************************************************************/
    def tokenize_line(self, line_num, offset, text):
        if (self.current_state == C_STATE_NONE):
            offset = self.tokenize_line_normal(line_num, offset, text)
        elif (self.current_state == C_STATE_C_COMMENT):
            offset = self.tokenize_line_c_comment(line_num, offset, text)
        elif (self.current_state == C_STATE_CPP_COMMENT):
            offset = self.tokenize_line_cpp_comment(line_num, offset, text)
        elif (self.current_state == C_STATE_DQ_LITERAL):
            offset = self.tokenize_line_dq_literal(line_num, offset, text)
        elif (self.current_state == C_STATE_SQ_LITERAL):
            offset = self.tokenize_line_sq_literal(line_num, offset, text)
        else:
            print_log(f'Invalid State! : {self.current_state}')
            exit(-1)
        return offset


    #/*****************************************************************************/
    #/* トークンへの分割                                                          */
    #/*****************************************************************************/
    def tokenize(self, input_lines):
        print_log(f'Tokenize : {self.parent.file_name}')
        line_num        = 0
        for line in input_lines:
            line_num += 1
            offset = 0
            line = replace_hard_tab(self.parent, line)            #/* ハードタブはややこしいので半角スペースに置き換える */
            while(offset != LINE_END_OFFSET):
                offset = self.tokenize_line(line_num, offset, line)
        return


class cCondition:
    __slots__ = ('if_sentence', 'elif_sentence', 'else_sentence', 'endif_sentence', 'valid_sentence')
    def __init__(self, parent):
        self.if_sentence    = None
        self.elif_sentence  = []
        self.else_sentence  = None
        self.endif_sentence = None
        self.valid_sentence = None
        return


class cSentence:
    __slots__ = ('parent', 'tokens', 'sentences', 'type')
    def __init__(self, parent, tokens):
        self.parent          = parent
        self.tokens          = tokens
        self.type            = SENTENCE_NONE
        return

    def get_text(self):
        text = self.tokens[0].text
        for token in self.tokens[1:]:
            text += ' ' + token.text
        return text

    def append_token(self, token):
        self.tokens.append(token)
        return


class cPreprocessor:
    __slots__ = ('parent', 'tokens', 'sentences', 'current_sentence', 'conditions', 'condition_stack')
    def __init__(self, parent, tokens):
        self.parent            = parent
        self.tokens            = tokens
        self.sentences         = []
        self.current_sentence  = cSentence(self, [])
        self.conditions        = []
        self.condition_stack   = []
        return

    def append_token(self, token):
        self.current_sentence.append_token(token)
        return


    def append_sentence(self):
        self.sentences.append(self.current_sentence)
        self.current_sentence = cSentence(self, [])
        return


    def print_all_conditions(self):
        print_log(f'print_all_conditions')
        for condition in self.conditions:
#           print_log(f'Line {condition.if_sentence.tokens[0].start.row}, #{condition.if_sentence.tokens[1].text}')
            print_log(f'Line {condition.if_sentence.tokens[0].start.row}, {condition.if_sentence.get_text()}')
            print_log(f'Line {condition.endif_sentence.tokens[0].start.row}, {condition.endif_sentence.get_text()}')

        return


    #/*****************************************************************************/
    #/* #include処理                                                              */
    #/*****************************************************************************/
    def handle_include(self, path):
        global g_cwd
        global g_include_paths

#       print_log(f'  #include : {path}')
        file_name = path[1:-1]
        if (path[0] == '<'):
            file_path = g_cwd + '\\' + file_name
            if (os.path.isfile(file_path)):
#               print_log(f'  file found! @ cd : {file_path}')
                inc_file = get_file_info(file_path)
                inc_file.tokenize_input_c_file()
                self.parent.add_include(inc_file)
                return

        for inc_path in g_include_paths:
            file_path = inc_path + '\\' + file_name
            if (os.path.isfile(file_path)):
#               print_log(f'  file found! @ {inc_path} : {file_path}')
                inc_file = get_file_info(file_path)
                inc_file.tokenize_input_c_file()
                self.parent.add_include(inc_file)
                return

        print_log(f'  file not found! : {path}')
        return


    #/*****************************************************************************/
    #/* #define解析                                                               */
    #/*****************************************************************************/
    def parse_define(self, parameters, position):
        macro           = cMacroDefine()
        macro.name      = parameters[0].text
        macro.file_info = self
        macro.position  = position

        if (len(parameters) == 1):
            print_log(f'  #define1 : {macro.name}')
#           self.parent.macros.append(macro)
            self.parent.macro_define(macro)
            return

        index = 1
        #/* 関数マクロの引数（関数マクロ定義では()はネストしない） */
        if (parameters[index].text == '('):
            macro.is_function = True
            index += 1
            while(parameters[index].text != ')'):
                if (parameters[index].text != ','):
                    macro.args.append(parameters[index].text)

                index += 1
            index += 1

        for parameter in parameters[index:]:
            print_log(f'  #define value : {parameter.text}')
            macro.value += parameter.text

        self.parent.macro_define(macro)
        return


    #/*****************************************************************************/
    #/* #undef解析                                                                */
    #/*****************************************************************************/
    def parse_undef(self, parameters):
        macro_name = parameters[0].text
        self.parent.macro_undef(macro_name)
        return


    #/*****************************************************************************/
    #/* プリプロセス処理                                                          */
    #/*****************************************************************************/
    def parse_directive(self, directive, parameters, position):
#       print_log(f'  {directive}')
        if (directive == '#include'):
            if (parameters[0].type == TOKEN_DQ_LITERAL):
#               print_log(f'{parameters[0].text[1:-1]}')
                self.handle_include(parameters[0].text)
        elif (directive == '#define'):
            self.parse_define(parameters, position)
        elif (directive == '#undef'):
            self.parse_undef(parameters)
        elif (directive == '#if') or (directive == '#ifdef') or (directive == '#ifndef'):
            
            new_condition = cCondition(self)
            new_condition.if_sentence = self.current_sentence

            if (directive == '#ifdef') or (directive == '#ifndef'):
                defined = self.parent.is_defined(parameters[0].text)
                if (directive == '#ifdef') and (defined):
                    print_log(f'valid #ifdef : {parameters[0].text}')
                    new_condition.valid_sentence = self.current_sentence
                elif (directive == '#ifndef') and (not defined):
                    print_log(f'valid #ifndef : {parameters[0].text}')
                    new_condition.valid_sentence = self.current_sentence
                else:
                    print_log(f'not valid for {directive} : {parameters[0].text}')
            else:
                pass

            self.condition_stack.append(new_condition)
            self.conditions.append(new_condition)
        elif (directive == '#elif'):
            current_condition = self.condition_stack[-1]
            current_condition.elif_sentence.append(self.current_sentence)
        elif (directive == '#else'):
            current_condition = self.condition_stack[-1]
            current_condition.else_sentence = self.current_sentence
        elif (directive == '#endif'):
            current_condition = self.condition_stack.pop(-1)
            current_condition.endif_sentence = self.current_sentence
        elif (directive == '#line'):
            print_log(f'#line! {parameters}')
        elif (directive == '#error'):
            print_log(f'something wrong!  error directive! {parameters[0].text}')
        elif (directive == '#pragma'):
            pass
        else:
            print_log(f'something wrong!  directive!')
            exit(-1)

        return



    #/*****************************************************************************/
    #/* プリプロセス処理                                                          */
    #/*****************************************************************************/
    def preprocess(self, root_file):
        print_log(f'------------------------------------------- preprocess all tokens ----------------------------------------------------')
        directive       = ''
        directive_pos   = None
        parameters      = []
        after_directive = False
        row = 0

        for token in self.tokens:
            #/* ロギング */
            if (token.start.row != row):
                position = f'{row} : '
                row = token.start.row
            else:
                position = f''

            if (token.type == TOKEN_LF):
                print_log(f'{position}{token.text}', end='')
            else:
                print_log(f'{position}{token.text} ', end='')
                if (token.type == TOKEN_COMMENT_C) or (token.type == TOKEN_COMMENT_CPP):
                    row = token.end.row


            #/* トークン処理 */
            if (token.type == TOKEN_COMMENT_C) or (token.type == TOKEN_COMMENT_CPP):
                self.append_token(token)
                self.append_sentence()
            elif (token.type == TOKEN_LF):
                if (directive != ''):
                    self.parse_directive(directive, parameters, directive_pos)
                    self.append_sentence()
                    directive       = ''
                    directive_pos   = None
                    parameters      = []
                    after_directive = False
            elif (token.type == TOKEN_DQ_LITERAL) or (token.type == TOKEN_SQ_LITERAL) or (token.type == TOKEN_CONSTANT):
                if (after_directive):
                    parameters.append(token)
                self.append_token(token)
            elif (token.type == TOKEN_IDENTIFIER) or (token.type == TOKEN_KEYWORD):
                if (directive == '#') and (token.text in C_DIRECTIVES):
                    directive += token.text
                    after_directive = True
#                   print_log(f'  DIRECTIVE : {directive}')
                elif (after_directive):
                    parameters.append(token)

                self.append_token(token)
            elif (token.type == TOKEN_PUNCTUATOR):
                if (directive == '') and (token.text == '#'):
                    directive     = '#'
                    directive_pos = token.start
                    self.current_sentence.type = SENTENCE_DIRECTIVE
                elif (after_directive):
                    parameters.append(token)

                self.append_token(token)
                if (token.text == ';') or (token.text == '{') or (token.text == '}'):
                    self.append_sentence()
            else: #/* (token.type == TOKEN_OTHER)*/
                print_log(f'something wrong!  other token! {token.text}')
                exit(-1)

        self.print_all_conditions()
        return


class cFileInfo:
    __slots__ = ('file_name', 'file_path', 'encoding', 'new_line_code', 'includes', 'tokenizer', 'tokenized', 'macros', 'typedefs', 'variables', 'functions', 'code_lines', 'use_hard_tab', 'preprocessor')
    def __init__(self, target_path):
        self.file_name        = os.path.basename(target_path)
        self.file_path        = os.path.dirname(target_path)
        self.encoding         = char_set_detection(g_target_file)                                    #/* 文字コード判定 */
        self.new_line_code    = new_line_code_detection(g_target_file, self.encoding)                #/* 改行コード判定 */
        self.includes         = []
        self.tokenizer        = cTokenizer(self)
        self.tokenized        = False
        self.preprocessor     = cPreprocessor(self, self.tokenizer.tokens)
        self.macros           = []
        self.typedefs         = []
        self.variables        = []
        self.functions        = []
        self.code_lines       = []
        self.use_hard_tab     = False
        return


    #/*****************************************************************************/
    #/* マクロの定義追加                                                          */
    #/*****************************************************************************/
    def add_include(self, path):
        if not path in self.includes:
            self.includes.append(path)
        return


    #/*****************************************************************************/
    #/* マクロの定義追加                                                          */
    #/*****************************************************************************/
    def macro_define(self, macro):
        print_log(f'  MACRO define : {macro.name}', end='')
        if (macro.is_function):
            args_text = ','.join(macro.args)
            print_log(f'({args_text})', end='')

        print_log(f' : {macro.value}')

        for index, tmp in enumerate(self.macros):
            if (macro.name == tmp.name):
                print_log(f'  Re-define macro! : {macro.name}')
                self.macros[index] = macro
                return

        self.macros.append(macro)
        return


    #/*****************************************************************************/
    #/* マクロの定義削除                                                          */
    #/*****************************************************************************/
    def macro_undef(self, macro_name):
        for index, tmp in enumerate(self.macros):
            if (macro_name == tmp.name):
                print_log(f'  Undef macro! : {macro_name}')
                self.macros.pop(index)
                return

        print_log(f'  undef name not found! : {macro_name}')
        return


    #/*****************************************************************************/
    #/* 入力ファイルの字句解析                                                    */
    #/*****************************************************************************/
    def tokenize_input_c_file(self):
        if (self.tokenized == False):
            print_log(f'tokenize_input_c_file : {self.file_name}')
            f = self.open_encoding()
            self.code_lines = f.readlines()
            self.tokenizer.tokenize(self.code_lines)
            self.tokenized = True
            f.close()
        else:
            print_log(f'tokenize_input_c_file already tokenized! : {self.file_name}')

        return


    #/*****************************************************************************/
    #/* マクロ定義の有無判定                                                      */
    #/*****************************************************************************/
    def is_defined(self, macro):
        return macro in self.macros

    #/*****************************************************************************/
    #/* 入力ファイルの解析処理                                                    */
    #/*****************************************************************************/
    def parse_input_c_file(self):
        global g_macro_defs

        self.macros = g_macro_defs                  #/* コマンドラインで指定されたマクロを自身で保持 */

        if (self.tokenized == False):
            f = self.open_encoding()
            self.code_lines = f.readlines()
            self.tokenizer.tokenize(self.code_lines)
            self.tokenized = True
            f.close()

        self.preprocessor.preprocess(self)
        return


    #/*****************************************************************************/
    #/* 文字コード別のファイルオープン処理                                        */
    #/*****************************************************************************/
    def open_encoding(self):
        target_file = self.file_path + '\\' + self.file_name
        enc = self.encoding
        if (enc == "Windows-1254") or (enc == "Windows-1252") or (enc == "MacRoman") or (enc == "ascii"):
            read_file = open(target_file, 'r')
        else:
            read_file = open(target_file, 'r', encoding=enc)

        return read_file



class cMacroDefine:
    __slots__ = ('name', 'value', 'is_function', 'args', 'file_info', 'position')
    def __init__(self):
        self.name        = ""
        self.value       = ""
        self.is_function = False
        self.args        = []
        self.file_info   = None
        self.position    = None
        return


#/*****************************************************************************/
#/* 全角文字文字を含む文字列の幅を数える                                      */
#/*****************************************************************************/
def get_text_width_with_full_width(line_text):
    count = 0
    for character in line_text:
        if (character == '\n'):
            #/* 改行コードはかぞえない */
            pass
        elif unicodedata.east_asian_width(character) in 'FWA':
            count += 2
        else:
            count += 1

    return count


#/*****************************************************************************/
#/* ハードタブを半角スペースに変換                                            */
#/*****************************************************************************/
def replace_hard_tab(file_info, line_text):
    position = 0
    output_text = ''
    for character in line_text:
        if (character == '\t'):
            offset = HARD_TAB_LENGTH - (position % HARD_TAB_LENGTH)
            output_text            += ' ' * offset
            position               += offset
            file_info.use_hard_tab  = True
        elif unicodedata.east_asian_width(character) in 'FWA':
            output_text            += character
            position               += 2
        else:
            output_text            += character
            position               += 1

    return output_text


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

#   print("macro define %s : %s" % (name, value))
    macro_def = cMacroDefine()

    if (result := RE_ARG_MACRO_ARGS.match(name)):
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
#/* コマンドライン引数処理                                                    */
#/*****************************************************************************/
def check_command_line_option():
    global g_include_paths
    global g_target_file

    option = ""
    sys.argv.pop(0)
    for arg in sys.argv:
#       print("arg : %s" % arg)
        if (result := RE_ARG_MACRO_VAL.match(arg)):
            #/* 値のあるマクロ定義 */
            macro_def = add_macro_def(result.group(1), result.group(2))
        elif (result := RE_ARG_MACRO_ONLY.match(arg)):
            #/* 値のないマクロ定義 */
            macro_def = add_macro_def(result.group(1), "")
        elif (result := RE_ARG_INC_PATH.match(arg)):
            #/* インクルードパス */
#           print("-I [%s]" % (inc_path))
            inc_path = result.group(1)
            append_wo_duplicate(g_include_paths, inc_path)
        elif (os.path.isfile(arg)):
            #/* 対象ファイル */
            print("Target File! : %s" % (arg))
            g_target_file = arg
        else:
            print("有効な引数ではありません : %s" % (arg))

    return


#/*****************************************************************************/
#/* ログ出力                                                                  */
#/*****************************************************************************/
def print_log(text, end='\n'):
    print(text.encode("cp932", errors="replace").decode("cp932"), end = end)
    print(text.encode("cp932", errors="replace").decode("cp932"), file=g_log_file, end = end)
    return


#/*****************************************************************************/
#/* 処理開始ログ                                                              */
#/*****************************************************************************/
def log_start():
    global g_log_file
    now = datetime.datetime.now()

    this_file_name = os.path.basename(__file__).replace('.py', '_')
    time_stamp = now.strftime('%Y%m%d_%H%M%S')
    log_path = this_file_name + time_stamp + '.txt'
    g_log_file = open(log_path, "w")

    start_time = time.perf_counter()
    now = datetime.datetime.now()
    print_log("処理開始 : " + str(now))
    print_log ("----------------------------------------------------------------------------------------------------------------")

    return start_time


#/*****************************************************************************/
#/* 処理終了ログ                                                              */
#/*****************************************************************************/
def log_end(start_time):
    end_time = time.perf_counter()
    now = datetime.datetime.now()
    print_log ("----------------------------------------------------------------------------------------------------------------")
    print_log("処理終了 : " + str(now))
    second = int(end_time - start_time)
    msec   = ((end_time - start_time) - second) * 1000
    minute = second / 60
    second = second % 60
    print_log("  %dmin %dsec %dmsec" % (minute, second, msec))
    return


#/*****************************************************************************/
#/* 登録されたファイル情報の取得()                                            */
#/*****************************************************************************/
def find_file_info(target_path):
    global g_file_infos

    for file_info in g_file_infos:
        if (file_info.file_name == os.path.basename(target_path)) and (file_info.file_path == os.path.dirname(target_path)):
            return file_info

    return None


#/*****************************************************************************/
#/* ファイル情報の取得（未登録の場合は登録）                                  */
#/*****************************************************************************/
def get_file_info(target_path):
    abs_path = os.path.abspath(target_path)

    file_info = find_file_info(abs_path)
    if (file_info == None):
        print_log(f'{abs_path} is not found! create new!')
        file_info = cFileInfo(abs_path)
        g_file_infos.append(file_info)
    else:
        print_log(f'{abs_path} is found!')


    return file_info


#/*****************************************************************************/
#/* コマンドラインオプションの表示                                            */
#/*****************************************************************************/
def log_comand_line_options(file):
    global g_include_paths
    global g_macro_defs

    print_log ('----------------------------------------------------------------------------------------------------------------')
    print_log (f'コマンドラインオプション(対象ファイル) : {file}')
    count = 0

    print_log ("コマンドラインオプション(インクルードパス)")
    count = 0
    for inc_path in g_include_paths:
        print_log("  [%d]%s" % (count, inc_path))
        count += 1

    print_log ("コマンドラインオプション(マクロ定義)")
    count = 0
    for macro_def in g_macro_defs:
        if (macro_def.is_function):
            print_log("  [%d]%s(%s) : %s" % (count, macro_def.name, (',').join(macro_def.args), macro_def.value))
        else:
            print_log("  [%d]%s : %s" % (count, macro_def.name, macro_def.value))
        count += 1

    return



#/*****************************************************************************/
#/* 文字コードの見極め                                                        */
#/*****************************************************************************/
def char_set_detection(target_path):
    bin_file = open(target_path, 'rb')
    bin_data = bin_file.read(1024*1024)
    enc = chardet.detect(bin_data)
    bin_file.close()
    print_log(f'char_set_detection [{target_path}] is {enc['encoding']}')
    return enc['encoding']


#/*****************************************************************************/
#/* 改行コードの見極め                                                        */
#/*****************************************************************************/
def new_line_code_detection(target_path, encoding_set):
    f = open(target_path, newline='', encoding=encoding_set)
    ret = NEW_LINE_CODE_NONE
    for line in f:
        if line.endswith('\r\n'):
            tmp = NEW_LINE_CODE_CRLF
        elif line.endswith('\n'):
            tmp = NEW_LINE_CODE_LF
        elif line.endswith('\r'):
            tmp = NEW_LINE_CODE_CR
        else:
            print_log(f'このファイルには改行コードがありません! : {target_path}')
            tmp = NEW_LINE_CODE_LF

        if (ret == NEW_LINE_CODE_NONE):
            ret = tmp
        elif (ret != tmp):
            print_log(f'このファイルには改行コードが混在しています! : {ret} & {tmp}')
            ret = NEW_LINE_CODE_MIX
    f.close()

    print_log(f'new_line_code_detection [{target_path}] is {ret}')
    return ret



#/*****************************************************************************/
#/* メイン関数                                                                */
#/*****************************************************************************/
def main():
    global g_file_infos

    check_command_line_option()
    start_time = log_start()

    log_comand_line_options(g_target_file)

    if (os.path.isfile(g_target_file)):
        file_info = get_file_info(g_target_file)
        file_info.parse_input_c_file()
    else:
        print_log(f'ターゲットファイルを指定してください')

    log_end(start_time)
    return


if __name__ == "__main__":
    main()
