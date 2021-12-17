# Standard Library API Documentation Guide

_Authors_: @shafreenAnfar @daneshk @praneesha  
_Reviewers_: @chamil321  
_Created_: 2021/10/08  
_Updated_: 2021/10/08

- [Overview](https://github.com/ballerina-platform/ballerina-standard-library/edit/main/docs/api-documentation-guide.md#overview)
- [Materializing the Above](https://github.com/ballerina-platform/ballerina-standard-library/edit/main/docs/api-documentation-guide.md#materializing-the-above)
- [Linking BBEs from API Docs](https://github.com/ballerina-platform/ballerina-standard-library/edit/main/docs/api-documentation-guide.md#linking-bbes-from-api-docs)
- [Guidelines and Best Practices](https://github.com/ballerina-platform/ballerina-standard-library/edit/main/docs/api-documentation-guide.md#guidelines-and-best-practices)
- [Anti-Patterns](https://github.com/ballerina-platform/ballerina-standard-library/edit/main/docs/api-documentation-guide.md#anti-patterns)
- [Additional Guidelines ](https://github.com/ballerina-platform/ballerina-standard-library/edit/main/docs/api-documentation-guide.md#additional-guidelines )
- [More Ballerina Doc Guidelines](https://github.com/ballerina-platform/ballerina-standard-library/edit/main/docs/api-documentation-guide.md#more-ballerina-doc-guidelines)

## Overview

API Docs is another attribute of Ballerina that is authored, maintained, and governed by the Standard Library team. This is the only official way in which the Standard Library team communicates the details of its modules in the form of documentation. 

The key purpose of API Docs is to help developers understand a Standard Library module in a quick and easy way. Therefore, the structure of them is organized in a top-down approach similar to a well written research paper, book, or newspaper article. Every module starts with the synopsis at the top and have all the fine-grained details explained towards the bottom. Basically, as you continue downwards, the details increase gradually until you have all the information. 

The following is the high-level structure of API Documentation.

- **Topic** - The module name.
- **Overview** - A high-level description of the module, which includes concepts, philosophies, standards, practises, motives, etc., which were followed when designing the module. You should be able to understand the overall purpose of this module as a whole by reading this. Basically, this includes the synopsis of the module. 
- **Sub Topics** - After the high-level purpose of the module is understood, you can dig deeper into understanding the functions, objects, records, etc. of the module.

A good example for the above can be found in the [GO Standard Library Docs](https://pkg.go.dev/regexp#example_) and [Java™ Platform, Standard Edition 7
API Specification](https://docs.oracle.com/javase/7/docs/api/).

## Materializing the Above

The three components below are used to materialize the above.

1.  `Package.md` documentation 
      -  This is all about the distribution of the modules. The content of this is rendered in Ballerina Central (but not in API Docs of [lib.ballerina.io`](https://lib.ballerina.io/)). 
      -  This can include elements such as a banner mentioning that this is owned by the Standard Library team, the version compatibility, release dates, governing principles, security validations, etc.
2. `Module.md` documentation 
   -  Default `Module.md` file 
       - By default, the `Module.md` file acts as the root description. Basically, this corresponds to the `Overview` section in API Docs. This includes the synopsis of this module. 
   -  Other `Module.md` files 
      -  All the other module files fall under the `Sub Topics` section, which will include a synopsis specific to that particular module.
   - Use code snippets if it helps to solidify the message.
       - Remember to evolve those along with the code.
   -  Pointing to BBEs  (More on that later).
3. Code documentation 
   -  Falls under `Sub Topics`. However, this is the leaf-level information, which basically completes the message. There is no other information that goes beyond this.

## Linking BBEs from API Docs 

At the moment, some of the BBEs are authored, maintained, and governed by the Standard Library team.

The purpose of the BBEs is to give a quick look and feel of Ballerina. These examples need to be short and sweet. You can start trying out Ballerina using these examples. Also, they can be used as reminders or quick reference. One BBE should only be used to explain one concept. You can dig deeper by referring API Docs or by using the Visual Studio Code tool itself, which provides other suggestions. Therefore, BBEs do not have to include every minor detail of the module. A good example would be the [UDP Client](https://ballerina.io/learn/by-example/udp-client.html). 

BBEs and API Docs are two documents are completely different from each other and serve completely two different purposes. Therefore, linking API Docs to BBEs sort of breaks the flow of API Docs. If examples are needed to solidify the message, better to write them then and there.

Also, BBEs could be owned by an external entity (e.g., the DevRel team) and be evolved on their own whereas, API docs are always authored, maintained, and governed by the Standard Library team. However, if required, BBEs can be added as another section in API Docs as similar communities (e.g., GoLang) have done it.

In fact, as BBEs are short and do not explain the complete picture, they should be linked to API docs so that you can refer API docs to know more information about the particular module. 

## Guidelines and Best Practices
1. Do NOT add full stops for any of the parameter descriptions.
      - **Incorrect:** # + url - Target service URL.
      - **Correct:**   # + url - Target service URL
2. Add full stops in the function/record/object/method/constant descriptions (found in code comments).
      -  **Incorrect:** # Attaches a service to the listener
      -  **Correct:**   # Attaches a service to the listener.
3. Start all descriptions with a capital letter (just for consistency as most are written like this now.)
      -  **Incorrect:** + url - target service URL
      -  **Correct:**  + url - Target service URL
4.  Avoid repeating the `returns` word when documenting the function returns. Just mention what is being returned.
      -  **Incorrect:**   \# + return - Returns the response of the request or an error if failed to establish the communication with the upstream server 
      -  **Correct:**   # + return - The response of the request or else an `http:Error` if failed to establish the communication with the upstream server
      -  When you have more than one returned items:
         -  \# + return - Generated string token,  an `auth:Error` occurred while generating the token, or else () if nothing is to be returned
         -  \# + return - `true` if authentication is successful, `false` otherwise, or else an `auth:Error` occurred while authenticating the credentials.
5.  Do NOT use "we" or "please" anywhere in technical docs. Always, use the passive form or direct form to say "you need to...".
      -  **Incorrect:** # For details, please see the WebSocket module.
      -  **Correct:**   # For details, see the WebSocket module.
6.  Keep comments in the singular form (e.g., "# Attaches..").
      -  **Incorrect:** # Attach a service to the listener.
      -  **Correct:**   # Attaches a service to the listener.
7.  Use code snippets if it helps to solidify the message.
      - Remember to evolve those along with the code.
      - Do NOT link to BBEs from API Docs.
8.  Capitalize standard words like URL, HTTP, or JSON.
      -  **Incorrect:** # Creates http server endpoints.
      -  **Correct:**   # Creates HTTP server endpoints.
9.  Apply the title case to all the headings.
      -  **Incorrect:**: # Remote methods associated with a `websocket:Service`
      -  **Correct:**   # Remote Methods Associated with a `websocket:Service`
10.  Add the Oxford comma before “and” or “or” in lists.
      -  **Incorrect:** # + message - An HTTP outbound request message or any payload of type `string`, `xml`, `json`, `byte[]`, `io:ReadableByteChannel` or `mime:Entity[]`
      -  **Correct:** # + message - An HTTP outbound request message or any payload of type `string`, `xml`, `json`, `byte[]`, `io:ReadableByteChannel`, or `mime:Entity[]`
      -  **Note:** We do not need the Oxford comma when there are only 2 items in the list as follows. E.g.,

         ```
         foo or bar
         foo, bar, or baz
         foo and bar
         foo, bar, and baz
         ```
11. Capitalize all file extensions.
      -  **Examples:** BAL, ZIP
12. Use backticks to highlight the keywords.
      -  **Examples:** `websocket:Service`
13. For names of third party technologies, use the exact way they write it (Google and check). 
      -  **Examples:** `MySQL` not `Mysql` 
14.  Add one-line code snippets where possible. E.g., https://ballerina.io/v1-2/learn/api-docs/ballerina/java/index.html#annotations.
15.  All the referrences of records/objects/functions/methods inside the API docs and `Module.md` should have the representation as `<module-name>:<type-name>` instead of `<type-name>`.
16.  Any description related to the parameter, which goes beyond a single line should start with the starting position of the 1st line.
      - **Example:** # + httpClient - Chain of different HTTP clients which provides the capability   
    \# 		   for initiating contact with a remote HTTP service in resilient  
    \# 		   manner
17.  Do not use the word “users” in the comments. Instead, address the users directly using the word “you”. E.g.,
      -  **Incorrect:** Users can also pass a key/value pair where the value is an error stack trace.
      -  **Correct:** You can also pass a key/value pair where the value is an error stack trace.

## Anti-Patterns
For information on how to write better Ballerina code, see [Ballerina Anti-Patterns](https://docs.google.com/document/d/1y6QVqaZzZt9jMpYV4jP5WRS_W_KoC4y40Uuoh1ALu8E/edit?usp=sharing).

## Additional Guidelines 

1. Study the basics and best practices in writing API Docs comments. For information, go to [Documenting Ballerina Code](https://ballerina.io/learn/documenting-ballerina-code/).

2. API Docs need to explain what the module is about, when, and how it is used. It should not try to explain language features (e.g., error handling, concurrency, etc). The language-level features will have to be covered in the Learn pages. 

3. Module-level documentation page needs to introduce the general concept of the module and the main APIs that are used. For example, in the I/O module, this would be the aspects such as the channels concept, how we have different types of channels etc., and their common behavior. 

   Rust’s I/O API documentation](https://doc.rust-lang.org/std/io/index.html) is a good example for how similar communities have done this. After the module overview, for each object, record, function, a separate documentation page is added, which will contain their individual details and also their specific examples. For example, see [Struct std::io::Cursor](https://doc.rust-lang.org/std/io/struct.Cursor.html) and [Struct std::io::BufReader](https://doc.rust-lang.org/std/io/struct.BufReader.html). Some APIs that were featured in the main module page will need to again have their own examples in their respective page. Therefore, there will be some overlap of information in that area. 

4. The examples in the API Docs need to be short. Mostly, shorter than BBEs. They usually explain a quick API operation and not a complete, end to end scenario. The same [Ballerina By Examples Guidelines](https://github.com/ballerina-platform/ballerina-distribution/blob/master/doc-guidelines.md#ballerina-by-examples-guidelines) should be used for API Docs as well to keep the examples simple and precise. 

5. You should NOT try to refer to the BBEs with links from within API Docs, but rather have separate examples. This is because the required examples will probably not match the examples in the BBEs. The API Docs should have more examples to explain each API operation etc. Also, you will not want to click another link and navigate away from the API docs to a separate BBE page. Rather, you will need to see the example in the same place where the module is described. 

6. In scenarios such as error value returns, all possible error types and their scenarios should be mentioned clearly. There should NOT be statements such as “returns error when something goes wrong”. 

## More Ballerina Doc Guidelines

For more information on Ballerina doc guidelines, see [Ballerina Doc Guidelines](https://github.com/ballerina-platform/ballerina-distribution/blob/master/doc-guidelines.md).
