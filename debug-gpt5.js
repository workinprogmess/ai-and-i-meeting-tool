#!/usr/bin/env node

require('dotenv').config();
const OpenAI = require('openai');

async function debugGPT5() {
    const openai = new OpenAI({
        apiKey: process.env.OPENAI_API_KEY
    });
    
    console.log('🔍 debugging gpt-5 response structure...\n');
    
    try {
        const response = await openai.chat.completions.create({
            model: 'gpt-5',
            messages: [
                {
                    role: 'user',
                    content: 'write a short summary of this meeting: person A said hello, person B said goodbye.'
                }
            ],
            max_completion_tokens: 4000
        });
        
        console.log('📝 full response structure:');
        console.log(JSON.stringify(response, null, 2));
        
        console.log('\n📄 choices[0]:');
        console.log(JSON.stringify(response.choices[0], null, 2));
        
        console.log('\n💬 message content:');
        console.log('content:', response.choices[0].message.content);
        console.log('content type:', typeof response.choices[0].message.content);
        console.log('content length:', response.choices[0].message.content?.length || 0);
        
        console.log('\n📊 usage:');
        console.log(JSON.stringify(response.usage, null, 2));
        
    } catch (error) {
        console.error('❌ error:', error.message);
        console.error('full error:', error);
    }
}

if (require.main === module) {
    debugGPT5().then(() => {
        console.log('\n✅ debug complete');
        process.exit(0);
    }).catch(error => {
        console.error('💥 debug failed:', error);
        process.exit(1);
    });
}

module.exports = debugGPT5;