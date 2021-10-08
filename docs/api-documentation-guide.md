# The Standard Library API Documentation Guide

_Authors_: @shafreenAnfar @daneshk @praneesha  
_Reviewers_: @chamil321  
_Created_: 2021/10/08  
_Updated_: 2021/10/08

## Overview

API docs is another attribute that is authored, maintained and governed by the Standard Library team. This is the only official way in which the standard library team communicates about its module details in form of documentation. 

The key purpose of this document is to help developers understand a given standard library module when needed in a quick and easy way. Therefore the structure of this document no is different from a well written research paper, book or newspaper article. In each case you start from top to bottom. At the top we have the synopsis whereas at the bottom we have all the fine-grained details. Basically, as you continue downwards, the details increase until you have all the information. The same applies for API docs as well but expressed in a different way.

Following is the high level structure of API documentation.

- **Topic** - In this its the module name
- **Overview** - A high level description of the module which includes things such as concepts, philosophies, standards, practises, motives, etc which we followed when designing the module. Once read one should be able to understand the overall purpose of this module as a whole. Basically this includes the synopsis of the package. 
- **Sub Topics** - Once understood the high level purpose of the module. If interested,  developers can further dig deeper into understanding modules functions, objects, records, etc.

A good example for the above can be found in [1](https://pkg.go.dev/regexp#example_) and [2](https://docs.oracle.com/javase/7/docs/api/).

## Materializing the Above

In order to materialize the above we need make use of three things,

-  Package.md documentation 
   -  This is all about the distribution of the modules. Rendered in Ballerina central but not in API docs of ballerina.io 
   -  This can include stuff like a banner saying this is owned by the standard library team, version compatibility, release dates, governing principles, security validations, etc.
- Module.md documentation 
   -  Default Module.md 
       - Module.md in the default acts as the root description. Basically this corresponds to what is discussed in point 2 above (Overview section). This includes the synopsis of this module. 
   -  Other Module.md 
      -  All the module files fall under point 3 above (Sub Topics) which includes a synopsis specific to that particular module.
   - Can use code snippets if it helps solidify the message
       - Remember to evolve those along with the code
   -  Pointing to BBEs  (More on that later)
- Code documentation 
   -  Falls under point 3 above (Sub Topics). However, this is the leaf level information which basically completes the message. There is no other information that goes beyond this.



## Ballerina by Examples (BBEs)

At the moment some of the BBEs are authored, maintained and governed by the standard library team.

The purpose of this document is to give a quick look and feel of Ballerina. These examples need to be short and sweet. Developers can start trying out Ballerina using these examples. Also, can be used as a reminder or quick reference.

One BBE should only be used to explain one concept.

If they are interested they can further dig deep by looking into API docs or by using VSCode tool itself which provides other sorts of suggestions.

Therefore, we believe BBEs do not have to include every little detail of the module. A good example would be [1](https://ballerina.io/learn/by-example/udp-client.html). 

## Linking BBEs from API Docs

Those two documents are completely different from each other and serve completely two different purposes. Therefore linking API docs to BBEs sort of breaks the flow of API docs. 
If examples are needed to solidify the message, better to write it then and there.

Also, some day BBEs could be even owned by an external entity (ex. DevRel team) and be evolved on their own whereas API docs are alway authored, maintained and governed by the standar library team.

If we are to add BBEs, I think we should do it as GoLang has done. Added it as another section of API docs.

In fact, IMO, linking should be done the other way around. BBEs should be linked to API docs. Because BBEs are short and incomplete. Therefore if one wants to know more information about the particular module that person can refer to API docs.  

## Guidelines and Best Practices
- Do not add full stops for any of the parameter descriptions
  - Incorrect: # + url - Target service URL.
  - Correct:   # + url - Target service URL
- Add full stops in the function/record/object/const descriptions (in comments).
  -  Incorrect: # Attaches a service to the listener
  -  Correct:   # Attaches a service to the listener.
- Start all descriptions  with a capital letter (just for consistency as most are written like this now.)
  -  Incorrect: + url - target service URL
  -  Correct:   + url - Target service URL
-  Avoid repeating the 'returns' word when documenting the function returns. Just mention what is being returned.
    -  Incorrect:   \# + return - Returns the response of the request or an error if failed to establish the communication with the upstream server 
    -  Correct:   # + return - The response of the request or else an `http:Error` if failed to establish the communication with the upstream server
   -  When you have more than one returned items:
      -  \# + return - Generated string token,  an `auth:Error` occurred while generating the token, or else () if nothing is to be returned
      -  \# + return - `true` if authentication is successful, `false` otherwise, or else an `auth:Error` occurred while authenticating the credentials.
-  Do NOT use "we" or "please" anywhere in technical docs. Always use the passive form or direct form to say "you need to...".
   -  Incorrect: # For details, please see the WebSocket module.
   -  Correct:   # For details, see the WebSocket module.
-  For comments, it should always be the singular form. "# Attaches.."
   -  Incorrect: # Attach a service to the listener.
   -  Correct:   # Attaches a service to the listener.
-  Can use code snippets if it helps solidify the message
    - Remember to evolve those along with the code
    - Pointing to BBEs  (More on that later)
- Code documentation 
   -  Falls under point 3 above (Sub Topics). However, this is the leaf level information which basically completes the message. There is no other information that goes beyond this.
-  Capitalize standard words like URL, HTTP, or JSON.
   -  Incorrect: # Creates http server endpoints.
   -  Correct:   # Creates HTTP server endpoints.
-  Add the Oxford comma before “and” or “or” in lists.
   -  Incorrect: # + message - An HTTP outbound request message or any payload of type `string`, `xml`, `json`, `byte[]`, `io:ReadableByteChannel` or `mime:Entity[]`
   -  Correct: # + message - An HTTP outbound request message or any payload of type `string`, `xml`, `json`, `byte[]`, `io:ReadableByteChannel`, or `mime:Entity[]`
   -  Note: We do not need the Oxford comma when there are only 2 items in the list as follows. E.g.,

```
foo or bar
foo, bar, or baz
foo and bar
foo, bar, and baz
```
-  Capitalize all file extensions.
   -  Examples: BAL, ZIP
-  For names of third party technologies, use the exact way they write it (Google and check). 
   -  Examples: MySQL not Mysql 
-  Add one line code snippet if possible. E.g., https://ballerina.io/v1-2/learn/api-docs/ballerina/java/index.html#annotations.
-  All the referrings of records/objects/functions inside the API docs and Module.md should have the representation as `<module-name>:<type-name>` instead of `<type-name>`.
-  Any description related to the parameter goes beyond a single line, and should start with the starting position of the 1st line.
   - Example: # + httpClient - Chain of different HTTP clients which provides the capability   
    \# 		   for initiating contact with a remote HTTP service in resilient  
    \# 		   manner
-  Do not use the word “users” in the comments. Instead, address the users directly using the word “you”. E.g.,
   -  Wrong: Users can also pass a key/value pair where the value is an error stack trace.
   -  Right: You can also pass a key/value pair where the value is an error stack trace.

## Anti-Patterns
[This doc](https://docs.google.com/document/d/1y6QVqaZzZt9jMpYV4jP5WRS_W_KoC4y40Uuoh1ALu8E/edit?usp=sharing) basically explains how to write better Ballerina code.

## Additional Guidelines 

[This link](https://github.com/ballerina-platform/ballerina-distribution/blob/master/doc-guidelines.md#ballerina-by-examples-guidelines) has additional information with regard to writing BBEs and API documentation.

