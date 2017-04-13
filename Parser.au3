; This file include every function strictly related to the parsing of data in .lua files

; Get the first comment block after $CarretPos
; We will also grab function declaration if possible/applicable
; The return is a Array : CarretPosition|BlockContent|Declaration|CarretPositionStart
Func ReadNextBlock($File, $CarretPos)
	local $CommentBlock = "" ; This is where we'll store the comment block
	local $Declaration = "" ; This is the next line after the comment block : usually the declaration statement
	local $CurrentLine = ""
	local $CurrentCarretPos = 0

	local $IsCommentBlock = False

	local $RegExResult
	local $RegexPos

	; Start reading from $CarretPos
	FileSetPos($File, $CarretPos, $FILE_BEGIN)

	; Read till we find a comment block
	Do
		$CurrentLine = FileReadLine($File)
		If @error Then ; We probably reached the eof
			Local $ReturnArray[3] = [$CurrentCarretPos, "", ""]
			Return $ReturnArray
		ElseIf StringInStr($CurrentLine, "---") Then
			$IsCommentBlock = True
		EndIf
	Until $IsCommentBlock

	Local $CarretPosStart = FileGetPos($File) - StringLen($CurrentLine) - 2

	; Add the first line to our comment block
	$RegExResult = StringRegExp($CurrentLine, "---(.*)", $STR_REGEXPARRAYMATCH)
	If Not @error Then ; The first line of the comment could be empty !
		$CommentBlock &= $RegExResult[0]&@CRLF
	EndIf

	; Read the comment block
	Do
		$CurrentCarretPos = FileGetPos($File)
		$CurrentLine = FileReadLine($File)
		If StringInStr($CurrentLine, "--") Then ; If we can't find any "--" in the line, then it's not the comment block anymore
			$RegExResult = StringRegExp($CurrentLine, "--(.*)", $STR_REGEXPARRAYMATCH)
			If Not @error Then; The line of the comment could be empty !
				$CommentBlock &= $RegExResult[0]&@CRLF
			EndIf
		Else
			$IsCommentBlock = False
		EndIf
	Until Not $IsCommentBlock

	; We'll take the next line, as it might be the declaration statement
	$Declaration = $CurrentLine

	; let's do some cleanup
	$CommentBlock = StringRegExpReplace($CommentBlock, "(?m)^\h+", "") ;remove leading whitespaces
	$CommentBlock = StringRegExpReplace($CommentBlock, "(?m)\h+$", "") ;remove trailing whitespaces
	$CommentBlock = StringRegExpReplace($CommentBlock, "(?m)^[#]+", "") ; remove sequences of # at the start of a line
	$CommentBlock = StringRegExpReplace($CommentBlock, "(?m)^\h+", "") ;remove leading whitespaces again now that we removed the "#"s
	$CommentBlock = StringRegExpReplace($CommentBlock, "(?m)-{3,}", "") ;remove sequences of at least 3 "-" which will mess up markdown
	$CommentBlock = StringRegExpReplace($CommentBlock, "(?m)={3,}", "") ; remove sequences of at least 3 "=" which will mess up markdown

	Local $ReturnArray[4] = [$CurrentCarretPos, $CommentBlock, $Declaration, $CarretPosStart]
	Return $ReturnArray
EndFunc

; Parses the block and returns the data for one tag
; don't use it to find the function tag !
Func ParseForOneTag($Block, $Tag)
	Local $i = 1
	Local $DataArray[1]
	Local $RegexResult[1]
	Local $RegexPos = 1
	Local $Regex

	; If we look for @usage, then it's a multiline data, the regex is different
	If $Tag == "@usage" Then
		$Regex = "(?s)@usage(.*)"
		$RegexResult = StringRegExp($Block, $Regex, $STR_REGEXPARRAYMATCH, $RegexPos)
	Else
		$Regex = $Tag&"\h(.*)\s"
		$RegexResult = StringRegExp($Block, $Regex, $STR_REGEXPARRAYMATCH, $RegexPos)
	Endif

	If @error Then
		Return ""
	Else
		Return $RegexResult[0]
	EndIf

EndFunc   ;==>ReadOneTag

; Parses the block and returns the data for multiple tags in an array
; Don't use it for @param !
Func ParseForTags($Block, $Tag)
	Local $i = 1
	Local $DataArray[1]
	Local $RegexResult[1]
	Local $RegexPos = 1

	Local $Regex = $Tag&"(?m)\h([^\s]*)(?:\h)?([^\s]*)?(?:\h)?(.*)?$"
	; For each tag
	While True
		$RegexResult = StringRegExp($Block, $Regex, $STR_REGEXPARRAYMATCH, $RegexPos)
		$RegexPos = @extended
		If $RegexPos == 0 Then ; We couldn't find any tag
			If Not $DataArray[0] Then
				Return ""
			Else
				Return $DataArray
			EndIf
		EndIf

		; Add the tag to the array.The array looks like this : type1|param1|description1|type2...
		ReDim $DataArray[$i * 3]
		$DataArray[($i * 3) - 3] = $RegexResult[0]
		If $RegexResult[1] == "" Then
			$DataArray[($i * 3) - 2] = "self" ; if the first param doesn't have a name, then it's self
		Else
			$DataArray[($i * 3) - 2] = $RegexResult[1]
		EndIf
		$DataArray[($i * 3) - 1] = $RegexResult[2]
		$i += 1
	WEnd
EndFunc

; Parses both the comment block and the declaration to find the function name and it's type
; Compares both of them if possible, but will always return the one in the comment block if possible
Func ParseFunctionName($CommentBlock, $Declaration)
	local $RegExResult
	local $FunctionNameFromDec
	local $FunctionNameFromComment
	local $ReturnArray[2]

	; Parse for function name in both the comment block and the desclaration
	$RegExResult = StringRegExp($CommentBlock, "\@function\h(?:(\[.*\]\h))?(.*)", $STR_REGEXPARRAYMATCH)
	If Not @error Then
		$FunctionNameFromComment = $RegExResult[1]
	EndIf
	$RegExResult = StringRegExp($Declaration, "function\h(?:.*\:)?(.*)\(.*\)", $STR_REGEXPARRAYMATCH)
	If Not @error Then
		$FunctionNameFromDec = $RegExResult[0]
	EndIf

	; compare them to each other
	If $FunctionNameFromComment Then
		If $FunctionNameFromDec <> $FunctionNameFromComment Then
			FileWrite($Log,"CAUTION : The commented function doesn't match its declaration : "&$FunctionNameFromComment& " -> "&$Declaration&@CRLF)
		EndIf
		$ReturnArray[0] = $FunctionNameFromComment
	ElseIf $FunctionNameFromDec Then
		;FileWrite($Log, "CAUTION: No data matching @function found in block, inferring the function name from its declaration : "& $FunctionNameFromDec & @CRLF)
		$ReturnArray[0] = $FunctionNameFromDec
	Else
		$ReturnArray[0] = ""
		$ReturnArray[1] = ""
		return $ReturnArray
	EndIf

	;parses for function type in both the comment block and the desclaration
	local $TypeFromComment
	local $TypeFromDec

	$RegExResult = StringRegExp($Declaration, "function\h(.*):", $STR_REGEXPARRAYMATCH)
	If Not @error Then
		$TypeFromDec = $RegExResult[0]
	EndIf
	$RegExResult = StringRegExp($CommentBlock, "function\h\[parent=#(.*)\]", $STR_REGEXPARRAYMATCH)
	If Not @error Then
		$TypeFromComment = $RegExResult[0]
	EndIf

	; compare them to each other
	If $TypeFromComment Then
		If $TypeFromDec <> $TypeFromComment Then
			FileWrite($Log,"CAUTION : The commented function type doesn't match its declaration : "&$TypeFromComment& " -> "&$Declaration&@CRLF)
		EndIf
		$ReturnArray[1] = $TypeFromComment
	ElseIf $TypeFromDec Then
		;FileWrite($Log, "CAUTION: No function type found in block, inferring the function type from its declaration : "& $TypeFromDec & @CRLF)
		$ReturnArray[1] = $TypeFromDec
	Else
		$ReturnArray[0] = ""
		$ReturnArray[1] = ""
		return $ReturnArray
	EndIf

	Return $ReturnArray
EndFunc

; Specifically designed to parse for @param tags
; will verify the comment by matching with the declaration (theoretically, I'm pretty sure it's bugged)
Func ParseParams($CommentBlock, $Declaration)
	Local $ParamsFromComment = ParseForTags($CommentBlock, "@param")
	Local $RegExResult
	Local $RegexPos = StringInStr($Declaration, "(")
	Local $ParamsFromDec[0]
	Local $NbParam = 0

	If StringInStr($Declaration, ":") Then
		$NbParam = 1
		ReDim $ParamsFromDec[1]
		$ParamsFromDec[0] = "self"
	EndIf

	; extract params from function decaration
	While True
		$RegExResult = StringRegExp($Declaration, "([^,\(\)\h]+)", $STR_REGEXPARRAYMATCH, $RegexPos)
		$RegexPos = @extended
		If @extended == 0 Then ExitLoop

		$NbParam += 1
		Redim $ParamsFromDec[$NbParam]
		$ParamsFromDec[$NbParam-1] = $RegExResult[0]
	WEnd

	; compare these parameters with those found in the comment block
	If UBound($ParamsFromComment) <> UBound($ParamsFromDec)*3 Then
		FileWrite($Log, "CAUTION: The number of parameters don't match between the comment block and declaration "& @CRLF)
	Else

		For $i=0 To $NbParam-1
			If $ParamsFromDec[$i] <> $ParamsFromComment[($i*3)+1] Then
				FileWrite($Log, "CAUTION: Parameters missmatch between the comment block and declaration "& @CRLF)
				FileWrite($Log, $ParamsFromComment[($i*3)+1]& " -> " & $ParamsFromDec[$i]&@CRLF)
				ExitLoop
			EndIf
		Next
	EndIf

	Return $ParamsFromComment
EndFunc