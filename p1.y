%{
#include <stdio.h>
#include <string.h>
#include <errno.h>
#include <list>
#include <map>
#include <iterator>
#include <iostream>
  
#include "llvm/IR/LLVMContext.h"
#include "llvm/IR/Value.h"
#include "llvm/IR/Function.h"
#include "llvm/IR/Type.h"

#include "llvm/Bitcode/BitcodeReader.h"
#include "llvm/Bitcode/BitcodeWriter.h"
#include "llvm/Support/SystemUtils.h"
#include "llvm/Support/ToolOutputFile.h"
#include "llvm/IR/IRBuilder.h"
#include "llvm/Support/FileSystem.h"

using namespace llvm;
using namespace std;

extern FILE *yyin;
int yylex(void);
int yyerror(const char *);

// From main.cpp
extern char *fileNameOut;
extern Module *M;
extern LLVMContext TheContext;
extern Function *Func;
extern IRBuilder<> Builder;

// Used to lookup Value associated with ID
map<string,Value*> idLookup;
 
%}

%union {
  int num;
  char *id;
  Value* val;
  std::list<Value*> *toe_list;
}

%token ID NUM MINUS PLUS MULTIPLY DIVIDE LPAREN RPAREN SETQ SETF AREF MIN MAX ERROR MAKEARRAY

%type <num> NUM 
%type <id> ID
%type <val> expr program 
%type <val> exprlist token token_or_expr
%type <toe_list> token_or_expr_list

%start program

%%


program: exprlist 
{                        
  Builder.CreateRet($1);
  return 0;
}
;

exprlist:  exprlist expr
{
  $$ = $2;                       
} 
| expr
{
  $$ = $1;                     
}
;         

expr: LPAREN MINUS token_or_expr_list RPAREN
{ 
    if ($3->size() != 1)
    {
      std::cout << "syntax error!" << std::endl;
      YYABORT;
    }
    else
    {
      $$ = Builder.CreateNeg($3->front());   
    }
  
}

| LPAREN PLUS token_or_expr_list RPAREN
{
  $$ = Builder.getInt32(0);
  for(std::list<Value*>::iterator it=$3->begin(); it != $3->end(); ++it)
  {
    $$ = Builder.CreateAdd($$,*it);
  }
}

| LPAREN MULTIPLY token_or_expr_list RPAREN
{
  $$ = Builder.getInt32(1);
  for(std::list<Value*>::iterator it=$3->begin(); it != $3->end(); ++it)
  {
    $$ = Builder.CreateMul($$,*it);
  }
}

| LPAREN DIVIDE token_or_expr_list RPAREN
{
  $$ = $3->front();
  for(std::list<Value*>::iterator it=std::next($3->begin(),1); it != $3->end(); ++it)
  {
    $$ = Builder.CreateFDiv($$,*it);
  }
}

| LPAREN SETQ ID token_or_expr RPAREN   
{
  Value* var = NULL;
  if(idLookup.find($3)==idLookup.end())
  {
    var = Builder.CreateAlloca(Builder.getInt32Ty(),nullptr,$3);
    idLookup[$3]=var;
  }
  else
  {
    var = idLookup[$3];
  }
  Builder.CreateStore($4,var);
}

| LPAREN MIN token_or_expr_list RPAREN
{
  $$ = $3->front();
  for(std::list<Value*>::iterator it=$3->begin(); it != $3->end(); ++it)
  {
    Value* cmpslt = Builder.CreateICmpSLT($$,*it);
    $$ = Builder.CreateSelect(cmpslt,$$,*it);
  }

}

| LPAREN MAX token_or_expr_list RPAREN
{
  $$ = $3->front();
  for(std::list<Value*>::iterator it=$3->begin(); it!=$3->end(); ++it)
  {
    Value* cmpsgt = Builder.CreateICmpSGT($$,*it);
    $$ = Builder.CreateSelect(cmpsgt,$$,*it);
  }
}

| LPAREN SETF token_or_expr token_or_expr RPAREN
{
  LoadInst* var;
  var = dyn_cast<LoadInst>($3);
  Value* addr;
  addr = var->getPointerOperand();
  Builder.CreateStore($4, addr);
}

| LPAREN AREF ID token_or_expr RPAREN
{
  Value *var = NULL;
  var = Builder.CreateGEP(idLookup[$3],$4);
  $$ = Builder.CreateLoad(var,"a"); 
}

| LPAREN MAKEARRAY ID NUM token_or_expr RPAREN
{
  Value *var = NULL;
  var = Builder.CreateAlloca(Builder.getInt32Ty(),Builder.getInt32($4),$3);
  idLookup[$3]=var;
  for(int i=0;i<$4;i++)
  {
    Builder.CreateStore($5, Builder.CreateGEP(var,Builder.getInt32(i)));
  }
  $$=$5;
}
;

token_or_expr_list:   token_or_expr_list token_or_expr
{
  $1->push_back($2);
  $$ = $1;
}
| token_or_expr
{
  $$ = new std::list<Value*>;
  $$->push_back($1);
}
;

token_or_expr:  token
{
  Value* var = NULL;
  var = Builder.CreateLoad($1,"$1");
  $$ = var;
}

| expr
{
  $$ = $1;
}
; 

token:   ID
{
  if (idLookup.find($1) != idLookup.end())
    $$ = idLookup[$1];
  else
    {
      YYABORT;      
    }
}

| NUM
{
  Value* var = Builder.CreateAlloca(Builder.getInt32Ty(),nullptr,"num");
  Builder.CreateStore(Builder.getInt32($1),var);
  $$ = var;
}
;

%%

void initialize()
{
  string s = "arg_array";
  idLookup[s] = (Value*)(Func->arg_begin()+1);

  string s2 = "arg_size";
  Argument *a = Func->arg_begin();
  Value * v = Builder.CreateAlloca(a->getType());
  Builder.CreateStore(a,v);
  idLookup[s2] = (Value*)v;
}

extern int line;

int yyerror(const char *msg)
{
  printf("%s at line %d.\n",msg,line);
  return 0;
}
