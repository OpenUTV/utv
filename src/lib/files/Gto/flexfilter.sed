s,#include <FlexLexer.h>,#include <Gto/FlexLexer.h>,
s/class istream;/#include <iosfwd>/
s/(?<!std::)istream\*/std::istream*/
s/(?<!std::)ostream\*/std::ostream*/
s/Lexer\.cpp/FlexLexer.cpp/
s/(?<!std::)cin/std::cin/
s/(?<!std::)cout/std::cout/
s/(?<!std::)cerr/std::cerr/
s/ssize_t yyFlexLexer::LexerInput/size_t yyFlexLexer::LexerInput/
s/yy_create_buffer( std::istream& file, size_t size )/yy_create_buffer( std::istream& file, int size )/
s/yy_create_buffer( std::istream\* file, size_t size )/yy_create_buffer( std::istream* file, int size )/
