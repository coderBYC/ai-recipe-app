#include <string>
#include <iostream>
#include <fstream>
#include <vector>
#include <algorithm>
#include <cctype>
#include <functional>
#include <sstream>

using namespace std;

struct Pos{
    int line;
    int word;
    int letter;
};

vector<string> split(const string &data){
    vector<string> result; 
    istringstream iss(data);
        for(string s; iss >> s; ) result.push_back(s); 
    return result; 
}

// TODO
// reads in the text and the positions of the characters in the cipher;
// identifies each character in the text using the cipher, and assembles
// the secret message by appending each character to form a string 
string find_chars(const vector < vector <string> > &text, const vector <Pos> &numbers){
    




}



int main(){
    ifstream finCipher("cipher.txt"), finPosts("posts.txt");
    int line, word, letter;
    vector <Pos> positions; // vector of character locations
    string fullLine;
    vector <string> linez;
    vector <vector<string> > fullText; // vector of text

    if(!finCipher.good()){
        cout << "finCipher error" << endl; 
        return 1; 
    }

    if(!finPosts.good()){
        cout << "finCipher error" << endl; 
        return 1; 
    }

    // read in cipher clues
    Pos cipherPos;
    while (finCipher >> cipherPos.line >> cipherPos.word >> cipherPos.letter){
        positions.push_back(cipherPos);
    }
    finCipher.close();

    // read in text key
    while (getline(finPosts,fullLine)){
        linez = split(fullLine);
        fullText.push_back(linez);
    }
    finPosts.close();

    // DECRYPT CIPHER
    cout << find_chars(fullText,positions) << endl;

    return 0;
}