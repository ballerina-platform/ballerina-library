# The Zero Bug Policy 
_Author_: Shafreen Anfar  
_Reviewer_: Danesh Kuruppu  
_Created_: 2021/08/27  
_Updated_: 2021/08/27 

As mentioned earlier, the zero bugs policy is meant to emphasise our commitment to quality. The Zero Bug Policy is simple. All bugs take priority over all new feature development or improvements. That’s it. There is nothing more.

Usually before we merge any feature to master, spec and implementation needs to be complete and then there needs to be adequate thoughtful test-cases which cover all angles of the feature. These test cases should be documentation by example for the feature. 

However, even after that if the library user does report bugs, those bugs get priority over anything else. Because that is a direct hit on quality. Something we do not want to tolerate. In other words, somewhere in the process we have made a mistake which resulted in an incomplete feature. An incomplete feature shouldn’t have been merged to master in the first place. 

After all, remember our goal is to make the Ballerina user’s life fun and having to deal with bugs is certainly not fun. Therefore, the second best thing we can do is immediately fix it and minimize damage. 

Also doing so would make sure any other users won’t come across the same bug either. 

There could be bugs that are not worth investing effort on. There is very little gain by fixing those. In such cases, we can label it as `won’t fix` and close it after clearly explaining the reason for not fixing.

## Platform Support 
The standard library team has been working for many months to ensure that the team has the right platform to execute Zero Bugs Policy. Moving out to separate repositories, having the distributed build system, having the Ballerina-central support and finally the build-tool support are part of executing this policy.

Now the team is in a position to reap the benefits of this effort as the standard libraries could be instantly released to Ballerina-central which in turn make the latest compatible versions of the libraries available to users instantly.  
