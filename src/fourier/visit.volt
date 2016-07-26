// Copyright © 2016, Jakob Bornecrantz.  All rights reserved.
// See copyright notice in src/fourier/license.volt (BOOST ver. 1.0).
module fourier.visit;

import watt.io;
import watt.text.string : indexOf;

import lib.clang;

import fourier.walker;
import fourier.util;
import fourier.volt;

fn visit(cursor: CXCursor, p: CXCursor, ptr: void*) CXChildVisitResult
{
	w := cast(Walker)ptr;
	assert(w !is null);

	w.writeIndent();
	foo: i32;

	// Print the kind of node we are standing on.
	writef("+- %s ", cursor.kind.toString());

	// Print the type of this node.
	type := clang_getCursorType(cursor);
	if (type.kind != CXType_Invalid) {
		writef("   \"");
//		type.printType(w);
		writefln("\"");
	} else {
		writefln("");
	}

	// Visit children.
	w.indent++;
	clang_visitChildren(cursor, visit, ptr);
	w.indent--;

	// Done here.
	return CXChildVisit_Continue;
}

fn visitAndPrint(cursor: CXCursor, p: CXCursor, ptr: void*) CXChildVisitResult
{
	w := cast(Walker)ptr;
	assert(w !is null);

	switch (cursor.kind) {
	case CXCursor_TypedefDecl: doTypedefDecl(ref cursor, w); break;
	case CXCursor_FunctionDecl: doFunctionDecl(ref cursor, w); break;
	case CXCursor_StructDecl: doStructDecl(ref cursor, w); break;
	case CXCursor_UnionDecl: doUnionDecl(ref cursor, w); break;
	case CXCursor_VarDecl: doVarDecl(ref cursor, w); break;
	case CXCursor_IntegerLiteral: doIntLiteral(ref cursor, w); break;
	default:
	}

	foreach (_decl, _cursor; w.delayedAggregates) {
		doExplicitAggregateDecl(ref _cursor, w, _decl);
		w.delayedAggregates.remove(_decl);
	}

	return CXChildVisit_Continue;
}

fn assignVisitAndPrint(cursor: CXCursor, p: CXCursor, ptr: void*) CXChildVisitResult
{
	if (cursor.kind != CXCursor_VarDecl) {
		return CXChildVisit_Continue;
	}
	write(" = ");
	visitAndPrint(cursor, p, ptr);
	return CXChildVisit_Continue;
}

fn visitFieldAndPrint(cursor: CXCursor, ptr: void*) CXVisitorResult
{
	w := cast(Walker)ptr;
	assert(w !is null);

	switch (cursor.kind) {
	case CXCursor_FieldDecl:
		doVarDecl(ref cursor, w);
		break;
	default:
		break;
	}

	return CXVisit_Continue;
}

fn doTypedefDecl(ref cursor: CXCursor, w: Walker)
{
	type := clang_getTypedefDeclUnderlyingType(cursor);
	tdName := getVoltString(clang_getCursorSpelling(cursor));

	// struct Foo {}; typedef struct Foo Foo;
	typeName := getVoltString(clang_getTypeSpelling(type));
	canonical : CXType;
	clang_getCanonicalType(out canonical, type);
	canonicalCursor := clang_getTypeDeclaration(canonical);
	canonicalName := getVoltString(clang_getCursorSpelling(canonicalCursor));
	if (tdName == canonicalName && canonical.kind == CXTypeKind.CXType_Record) {
		return;
	}

	w.addBase(buildAlias(tdName, type.typeString(w, tdName)));
}

fn doFunctionDecl(ref cursor: CXCursor, w: Walker)
{
	funcName := getVoltString(clang_getCursorSpelling(cursor));

	Base[] args;
	Base[] rets;

	count := cast(u32)clang_Cursor_getNumArguments(cursor);
	foreach (i; 0 .. count) {
		arg := clang_Cursor_getArgument(cursor, i);
		argName := getVoltString(clang_getCursorSpelling(arg));
		type := clang_getCursorType(arg);
		args ~= buildArg(argName, type.typeString(w));
	}

	type := clang_getCursorType(cursor);
	ret := clang_getResultType(type);
	rets ~= buildReturn(ret.typeString(w));
	w.addBase(buildFunction(funcName, args, rets));
}

fn doStructDecl(ref cursor: CXCursor, w: Walker)
{
	doAggregateDecl(ref cursor, w, Kind.Struct);
}

fn doUnionDecl(ref cursor: CXCursor, w: Walker)
{
	doAggregateDecl(ref cursor, w, Kind.Union);
}

fn doExplicitAggregateDecl(ref cursor: CXCursor, w: Walker, decl: string)
{
	/*structType: CXType;
	clang_getCursorType(out structType, cursor);
	w.writeIndent();
	writeln(decl);
	writeln("{");
	w.indent++;
	w.pushAggregate(cursor);
	clang_Type_visitFields(structType, visitFieldAndPrint, cast(void*)w);
	w.popAggregate();
	w.indent--;
	writeln("}");*/
//	assert(false);
}

fn doAggregateDecl(ref cursor: CXCursor, w: Walker, kind: Kind)
{

	structType: CXType;
	clang_getCursorType(out structType, cursor);

	structName := getVoltString(clang_getCursorSpelling(cursor));
	isPrivate := false;
	if (structName == "") {
		idName := getVoltString(clang_getTypeSpelling(structType));
		structName = w.getAnonymousName(idName);
		isPrivate = true;
	}
	p : Parent = buildAggregate(kind, structName, []);
	w.pushAggregate(cursor, p);
	clang_Type_visitFields(structType, visitFieldAndPrint, cast(void*)w);
	w.popAggregate();
	w.addBase(p);
/*
	if (structName == "") {
idName := getVoltString(clang_getTypeSpelling(structType));
		structName = w.getAnonymousName(idName);
		isPrivate = true;
	}

	w.writeIndent();
	writef("%s%s %s\n", isPrivate ? "private " : "", keyword, structName);
	w.writeIndent();
	writef("{\n");

	w.indent++;
	w.pushAggregate(cursor);
	clang_Type_visitFields(structType, visitFieldAndPrint, cast(void*)w);
	w.popAggregate();
	w.indent--;

	w.writeIndent();
	writeln("}");*/
}

fn doVarDecl(ref cursor: CXCursor, w: Walker)
{
	type: CXType;
	clang_getCursorType(out type, cursor);

	declType := clang_getTypeDeclaration(type);
	if (clang_Cursor_isAnonymous(declType) &&
	    (declType.kind == CXCursor_UnionDecl ||
	    declType.kind == CXCursor_StructDecl)) {
		// TODO: Figure out a cleaner way to get this information.
		isUnion := getVoltString(clang_getTypeSpelling(type)).indexOf("union") >= 0;
		randomName := "__Anon" ~ w.random.randomString(6);
		w.delayAggregate((isUnion ? "union " : "struct ") ~ randomName, cursor);
//		w.writeIndent();
//		writefln("%s : %s;", w.getAnonymousAggregateVarName(isUnion ? "u" : "s"),
//		         randomName);
		w.addBase(buildVariable(w.getAnonymousAggregateVarName(isUnion ? "u" : "s"),
			randomName));
		return;
	}

	vName := getVoltString(clang_getCursorSpelling(cursor));
	w.addBase(buildVariable(vName, type.typeString(w, vName)));

	//if (w.isGlobal()) {
	//	writef("global ");
	//}
	//writef("%s : ", vName);
	//type.printType(w, vName);

	//clang_visitChildren(cursor, assignVisitAndPrint, cast(void*)w);

	//writefln(";");
}

fn doIntLiteral(ref cursor: CXCursor, w: Walker)
{
	/*range := clang_getCursorExtent(cursor);
	tokens: CXToken*;
	nTokens: u32;
	clang_tokenize(w.tu, range, &tokens, &nTokens);
	if (nTokens > 0) {
		str := getVoltString(clang_getTokenSpelling(w.tu, tokens[0]));
		write(str);
	}
	clang_disposeTokens(w.tu, tokens, nTokens);*/
}