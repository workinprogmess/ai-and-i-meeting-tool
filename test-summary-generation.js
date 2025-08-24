#!/usr/bin/env node

require('dotenv').config();
const SummaryGeneration = require('./src/api/summaryGeneration');

// sample meeting transcript for testing
const sampleTranscript = `
[0:00] speaker 1: alright everyone, thanks for joining. so we need to figure out this user onboarding issue. 

[0:15] speaker 2: yeah, the drop-off rate is pretty concerning. like 40% of users aren't completing the signup flow.

[0:25] speaker 1: sarah, you've been looking at the data - what's your take?

[0:30] speaker 2: well, i think the main issue is step 3. people get confused about the verification email. they either don't see it or don't know what to do with it.

[0:45] speaker 3: *joins late* sorry, traffic was terrible. what did i miss?

[0:50] speaker 1: we're talking about the onboarding flow. sarah thinks step 3 is the problem.

[1:00] speaker 3: oh definitely. i've been getting support tickets about that all week. people keep asking where the email went.

[1:10] speaker 2: exactly. and even when they find it, the email template is pretty confusing. it looks like spam.

[1:20] speaker 1: *sighs* okay, so we need to fix two things - the email delivery and the template design.

[1:30] speaker 3: i can handle the template redesign. probably need a day or two to test different versions.

[1:40] speaker 2: for delivery, maybe we should add better messaging on the page? like "check your inbox, including spam folder"?

[1:50] speaker 1: good idea. can you mock that up today?

[1:55] speaker 2: sure, i'll have something by end of day.

[2:05] speaker 1: perfect. mike, when can you get the new email template ready?

[2:10] speaker 3: let's say friday? i want to a/b test a few options first.

[2:20] speaker 1: sounds good. this should really help our conversion rate. anything else on this?

[2:30] speaker 2: nope, i think that covers it.

[2:35] speaker 1: alright, talk to you all tomorrow then.
`;

async function testSummaryGeneration() {
    console.log('🚀 testing ai&i summary generation with sally rooney style...\n');
    
    // check environment variables
    if (!process.env.OPENAI_API_KEY) {
        console.log('❌ missing OPENAI_API_KEY in .env file');
        return;
    }
    
    if (!process.env.GOOGLE_AI_KEY) {
        console.log('❌ missing GOOGLE_AI_KEY in .env file');
        return;
    }
    
    const summaryGen = new SummaryGeneration();
    
    const meetingOptions = {
        participants: ['team lead', 'sarah (designer)', 'mike (developer)'],
        duration: 3,
        topic: 'user onboarding optimization',
        context: 'weekly team meeting to solve conversion issues'
    };
    
    try {
        console.log('📝 generating summaries with both gpt-5 and gemini 2.5 pro...\n');
        
        const comparison = await summaryGen.compareProviders(sampleTranscript, meetingOptions);
        
        console.log('\n' + '='.repeat(60));
        console.log('GPT-5 SUMMARY');
        console.log('='.repeat(60));
        if (comparison.gpt5.error) {
            console.log(`❌ error: ${comparison.gpt5.error}`);
        } else {
            console.log(comparison.gpt5.summary);
            console.log(`\n💰 cost: $${comparison.gpt5.cost.totalCost.toFixed(4)}`);
            console.log(`⏱️  time: ${comparison.gpt5.processingTime}ms`);
        }
        
        console.log('\n' + '='.repeat(60));
        console.log('GEMINI 2.5 PRO SUMMARY');
        console.log('='.repeat(60));
        if (comparison.gemini.error) {
            console.log(`❌ error: ${comparison.gemini.error}`);
        } else {
            console.log(comparison.gemini.summary);
            console.log(`\n💰 cost: $${comparison.gemini.cost.totalCost.toFixed(4)}`);
            console.log(`⏱️  time: ${comparison.gemini.processingTime}ms`);
        }
        
        console.log('\n' + '='.repeat(60));
        console.log('ANALYSIS');
        console.log('='.repeat(60));
        console.log('recommendation:', comparison.recommendation);
        console.log('analysis saved to summaries/ folder');
        
    } catch (error) {
        console.error('❌ test failed:', error.message);
        console.error(error.stack);
    }
}

// run the test
if (require.main === module) {
    testSummaryGeneration().then(() => {
        console.log('\n✅ test complete!');
        process.exit(0);
    }).catch(error => {
        console.error('💥 test failed:', error);
        process.exit(1);
    });
}

module.exports = testSummaryGeneration;